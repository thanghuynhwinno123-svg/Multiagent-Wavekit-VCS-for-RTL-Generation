"""
agents/rag_agent.py
RAG Agent: đọc spec, phân tích chức năng module, suy ra testcase cần thiết.
"""
import os
import json
import re
import time
from dotenv import load_dotenv

from langchain_community.document_loaders import DirectoryLoader, UnstructuredFileLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import FAISS
from langchain_community.vectorstores.utils import DistanceStrategy
from langchain_community.embeddings import FastEmbedEmbeddings
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser

load_dotenv()

MODEL_NAME = os.environ.get("OPENAI_MODEL", "gpt-5.4")

BASE_DIR    = os.path.dirname(os.path.abspath(__file__))
SPEC_DIR    = os.path.join(BASE_DIR, "..", "spec")
CACHE_DIR   = os.path.join(BASE_DIR, "..", "fastembed_cache")
FAISS_CACHE = os.path.join(CACHE_DIR, "faiss_index")

_llm = ChatOpenAI(model=MODEL_NAME, temperature=0)

_RAG_PROMPT = """\
You are a senior verification engineer specializing in RTL/SystemVerilog.

Given the specification context below and the user's design request:

1. Identify ALL hardware modules that need to be designed.
2. For EACH module, analyze its FUNCTIONAL BEHAVIOR:
   - What distinct operations or functions does it perform?
   - What are input/output ports and their bit-widths?
3. Infer comprehensive testcases to thoroughly cover all operations, functions, and scenarios.
   Each testcase must:
   - Apply a concrete representative input stimulus (specific values for each input port).
   - State the expected output value(s).
   - Be named after the operation it exercises (e.g., "ADD: a=5 b=3 → result=8").

RULES for inferring testcases:
- Infer all necessary testcases to ensure comprehensive functional coverage for each module.
- For the TOP-level integration module (e.g., cpu_top, rv32e_mcu_cpu_top, rv32ec_zmmul_cpu_top, or any module ending in _top), infer testcases as OBSERVABLE INTEGRATION FLOWS, not hidden internal proofs.
- For such top-level modules, each inferred testcase MUST be checkable using only the top-level ports or architecturally observable external behavior.
- For datapath instruction classes such as ADD/SUB/AND/OR/XOR/shifts/SLT/MUL/compressed ALU forms, top-level testcases should focus on observable integration outcomes such as: instruction accepted, no unexpected trap, no fail_stop, correct request/redirect behavior, and any externally visible side effect actually exposed at the top interface.
- For flows with directly observable external effects (load/store handshake, branch/jump redirect, boot success/fail, interrupt/trap entry, MRET return, externally visible CSR/trap routing), inferred testcases should explicitly require those visible effects.
- Do NOT require the top-level module to prove hidden internal values such as regfile contents, internal ALU result buses, or internal CSR state unless those values are actually exposed at the top-level interface.
- Do NOT test mathematical properties (commutativity, associativity, etc.).
- Do NOT test stability, glitch, or timing properties.
- Do NOT test output-range validity.
- Do NOT test transitions between inputs.
- If the module has a synchronous reset or enable, add testcase(s) for reset/enable behavior if it is documented in the spec.
- For combinational modules with no clock/reset (e.g., adder, gate, mux), do NOT add any reset or clock testcase.
- For a module with N distinct operations, generate all testcases required to fully cover these operations and their potential boundary cases.

Specification Context:
{context}

User Request:
{question}

Return ONLY valid JSON:
{{
  "summary": "<brief description>",
  "modules": ["<module1>", "<module2>"],
  "module_analysis": {{
    "<module_name>": {{
      "description": "<what this module does>",
      "ports": {{
        "inputs":  [{{"name": "", "width": 0, "description": ""}}],
        "outputs": [{{"name": "", "width": 0, "description": ""}}]
      }},
      "inferred_testcases": [
        "<operation name>: <input stimulus> → <expected output>",
        "<operation name>: <input stimulus> → <expected output>"
      ]
    }}
  }}
}}

Return ONLY the JSON. No explanation.
"""

_rag_chain = ChatPromptTemplate.from_template(_RAG_PROMPT) | _llm | StrOutputParser()

_vectorstore = None


def _get_vectorstore():
    global _vectorstore
    if _vectorstore is not None:
        return _vectorstore

    os.makedirs(CACHE_DIR, exist_ok=True)
    loader = DirectoryLoader(
        path=SPEC_DIR,
        glob="**/*.md",
        loader_cls=UnstructuredFileLoader,
        show_progress=True,
        use_multithreading=True,
    )
    docs = loader.load()
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=1200, chunk_overlap=200,
        add_start_index=True, strip_whitespace=True
    )
    splits = splitter.split_documents(docs)
    embeddings = FastEmbedEmbeddings(
        model_name="BAAI/bge-base-en-v1.5",
        cache_dir=CACHE_DIR,
    )
    if os.path.exists(FAISS_CACHE):
        print("[RAG] Loading vectorstore from cache...")
        _vectorstore = FAISS.load_local(
            FAISS_CACHE, embeddings, allow_dangerous_deserialization=True
        )
    else:
        print("[RAG] Building vectorstore (first run)...")
        _vectorstore = FAISS.from_documents(
            documents=splits,
            embedding=embeddings,
            distance_strategy=DistanceStrategy.COSINE,
        )
        _vectorstore.save_local(FAISS_CACHE)
        print("[RAG] Vectorstore saved to cache.")
    return _vectorstore


def _safe_call(inputs: dict, max_retries: int = 5) -> str:
    retries = 0
    last_err = "(none)"
    while retries < max_retries:
        try:
            result = ""
            try:
                for chunk in _rag_chain.stream(inputs):
                    result += chunk
            except ValueError as e:
                last_err = str(e)
                if "No generation chunks were returned" in last_err:
                    result = ""
                else:
                    raise

            if not result.strip():
                try:
                    fallback = _rag_chain.invoke(inputs)
                    result = fallback if isinstance(fallback, str) else str(fallback)
                except Exception as invoke_err:
                    last_err = str(invoke_err)

            if not result.strip():
                retries += 1
                print(f"[RAG_AGENT] Empty/streamless response using model='{MODEL_NAME}'. Retry ({retries}/{max_retries})...")
                time.sleep(5)
                continue
            return result
        except Exception as e:
            err = str(e)
            last_err = err
            if "No generation chunks were returned" in err:
                retries += 1
                print(f"[RAG_AGENT] Stream returned no chunks from model='{MODEL_NAME}'. Retry ({retries}/{max_retries})...")
                time.sleep(5)
            elif "Rate limit" in err or "429" in err or "rate_limit_error" in err or "Concurrency" in err:
                retries += 1
                print(f"[RAG_AGENT] Rate limit/Concurrency. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            elif any(k in err for k in ["524", "timeout", "5xx", "503", "502", "500", "stream_read_error", "APIError", "InternalServerError", "Upstream request failed", "Upstream service temporarily unavailable", "temporarily unavailable", "Connection error", "APIConnectionError"]):
                retries += 1
                print(f"[RAG_AGENT] API error. Waiting 30s ({retries}/{max_retries})...")
                time.sleep(30)
            else:
                raise
    base_url = os.environ.get("OPENAI_BASE_URL", "(default OpenAI)")
    raise RuntimeError(
        f"[RAG_AGENT] Failed after max retries. model='{MODEL_NAME}' base_url='{base_url}' last_error='{last_err}'"
    )

def _parse_json(text: str) -> dict:
    text = text.strip()
    match = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.DOTALL)
    if match:
        text = match.group(1).strip()
    else:
        s, e = text.find("{"), text.rfind("}")
        if s != -1 and e > s:
            text = text[s:e+1]
    try:
        return json.loads(text)
    except Exception:
        print("[RAG_AGENT] JSON parse failed.")
        return {}


def run(user_prompt: str) -> dict:
    print("\n[RAG_AGENT] Retrieving spec context...")
    vs = _get_vectorstore()

    # ── Multi-query retrieval: tăng độ phủ spec ──────────────────────────────
    # Query 1: Prompt gốc của người dùng (k=12 để phủ rộng hơn)
    retriever_main = vs.as_retriever(search_kwargs={"k": 12})
    docs_main = retriever_main.invoke(user_prompt)

    # Query 2: Tập trung vào ports, interface, signals
    port_query = f"{user_prompt} ports signals interface input output bit-width"
    retriever_port = vs.as_retriever(search_kwargs={"k": 6})
    docs_port = retriever_port.invoke(port_query)

    # Query 3: Tập trung vào behavior, testcase, verification
    tc_query = f"{user_prompt} behavior testcase verification corner case reset enable"
    retriever_tc = vs.as_retriever(search_kwargs={"k": 6})
    docs_tc = retriever_tc.invoke(tc_query)

    # Gộp và loại bỏ trùng lặp theo nội dung
    seen_contents = set()
    all_docs = []
    for doc in docs_main + docs_port + docs_tc:
        content_key = doc.page_content[:100]  # dùng 100 ký tự đầu để dedup
        if content_key not in seen_contents:
            seen_contents.add(content_key)
            all_docs.append(doc)

    # Giới hạn tối đa 9 chunk để giảm tải context gửi sang plan/LLM downstream
    all_docs = all_docs[:9]
    raw_context = "\n\n".join(d.page_content for d in all_docs)

    print(f"[RAG_AGENT] Retrieved {len(all_docs)} unique spec chunks (from 3 queries).")
    print("[RAG_AGENT] Analyzing modules and inferring test cases...")
    result_text = _safe_call({"context": raw_context, "question": user_prompt})

    rag_context = _parse_json(result_text)
    rag_context["raw_context"] = raw_context

    modules  = rag_context.get("modules", [])
    analysis = rag_context.get("module_analysis", {})
    total_tc = sum(len(v.get("inferred_testcases", [])) for v in analysis.values())

    print(f"[RAG_AGENT] Found {len(modules)} modules, {total_tc} inferred test cases.")
    for mod, info in analysis.items():
        print(f"  \u2192 {mod}: {len(info.get('inferred_testcases', []))} test cases")
    return rag_context
