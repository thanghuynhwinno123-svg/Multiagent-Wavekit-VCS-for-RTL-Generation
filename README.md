# Multi-Agent WaveKit VCS for RTL Generation

Mạng lưới đa tác tử tự động hóa toàn diện quy trình thiết kế, kiểm thử và gỡ lỗi mã nguồn phần cứng (RTL) dựa trên các Mô hình ngôn ngữ lớn (LLM). Hệ thống tích hợp công cụ phân tích dạng sóng tốc độ cao **WaveKit** cùng trình mô phỏng **VCS** để thiết lập vòng lặp phản hồi khép kín (Verification In-The-Loop), giúp tự động phát hiện và sửa lỗi từ cú pháp đến chức năng.

---

## 🏗️ Kiến Trúc Hệ Thống (System Architecture)

Dưới đây là luồng vận hành chi tiết của hệ thống phối hợp đa tác tử:
---

## 🤖 Các Tác Tử Trong Hệ Thống (Agent Roles)

Hệ thống phân rã bài toán thiết kế vi mạch thành các nhiệm vụ chuyên biệt cho từng Agent:

*   **Plan Agent**: Tiếp nhận yêu cầu ban đầu (User Prompt), phối hợp với RAG Agent để phân tích đặc tả kỹ thuật (Spec) và lập kế hoạch sinh mã, phân phối luật thiết kế.
*   **RAG Agent**: Tra cứu dữ liệu, tài liệu kỹ thuật, tiêu chuẩn thiết kế từ tệp cấu trúc nguồn để cung cấp ngữ cảnh chính xác cho Plan Agent.
*   **RTL Agent**: Chịu trách nhiệm tạo mã nguồn phần cứng dựa trên kế hoạch cấu trúc đã phê duyệt.
*   **Testbench Agent**: Sinh mã kiểm thử môi trường (Testbench) nhằm mô phỏng và xác thực các kịch bản phần cứng.
*   **Syntax Agent**: Trình biên dịch thu nhỏ sử dụng VCS kiểm tra lỗi cú pháp (`file.log`). Nếu có lỗi (`FAIL`), chuyển sang bộ nhớ cú pháp để yêu cầu sửa lại mã.
*   **TestCase Agent**: Tạo lập các kịch bản kiểm thử biên, phân tích các trường hợp thiếu kịch bản kiểm thử (`Miss Testcase`) lưu vào `TestCase Memory`.
*   **Functional Agent**: Thực thi chạy mô phỏng chính thức, tạo file bao bọc (`Gen Wrapper file`), mở lại Testbench nếu phát hiện lỗi logic chức năng (`Functional Bug`).
*   **Debug Agent**: Tiếp nhận các lệnh phân tích gỡ lỗi dựa trên kết quả kết xuất xung sóng để tái cấu trúc ngữ cảnh sửa lỗi cho Testbench hoặc cấu trúc mạch.

---

## 🛠️ Công Cụ Tích Hợp (Core Tools)

*   **VCS (Synopsys Verilog Compiler Simulator)**: Trình mô phỏng phần cứng chất lượng thương mại, chịu trách nhiệm biên dịch, kiểm tra cú pháp và chạy mô phỏng logic.
*   **WaveKit Tool**: Công cụ phân tích dạng sóng tốc độ cao tự động, giúp trích xuất thông tin sai lệch logic giữa các xung tín hiệu khi mô phỏng thất bại và gửi báo cáo về cho `Debug Agent`.

---

## 📁 Cấu Trúc Thư Mục Project

```text
├── RV32REC_Zmmul/      # Chứa mã nguồn thiết kế mẫu cho tập lệnh RISC-V (Zmmul)
├── agents/             # Định nghĩa cấu trúc, prompt và hành vi của hệ thống Đa tác tử
├── cache/              # Bộ lưu trữ tạm thời trạng thái hệ thống và luồng pipeline 
├── core/               # Các mô-đun lõi kết nối LLM và quản lý vòng lặp phản hồi
├── memory/             # Lưu trữ lịch sử lỗi cú pháp và lỗi chức năng phần cứng
├── reports/            # Xuất báo cáo kết quả kiểm thử và độ bao phủ (Coverage)
├── runlog/             # Nhật ký biên dịch trực tiếp từ VCS compiler
├── spec/               # Nơi chứa các tệp đặc tả kỹ thuật đầu vào (PDF/Text)
├── tools/              # Trình bao bọc cho WaveKit phân tích sóng và tập lệnh gọi lệnh VCS
├── main.py             # Điểm chạy kiểm thử cấu hình chính của toàn bộ hệ thống
└── .env                # Quản lý khóa cấu hình API của LLM (OpenAI, Anthropic, v.v.)
```

---

## 🚀 Hướng Dẫn Cài Đặt và Sử Dụng

### 1. Cài đặt môi trường
Đảm bảo hệ thống của bạn đã cài đặt sẵn **Synopsys VCS** và công cụ **WaveKit** trong biến môi trường hệ thống.

```bash
# Bản sao mã nguồn dự án
git clone https://github.com
cd Multiagent-Wavekit-VCS-for-RTL-Generation

# Cài đặt các thư viện Python phụ thuộc
pip install -r requirements.txt
```

### 2. Cấu hình biến môi trường
Tạo tệp `.env` tại thư mục gốc và cấu hình API Key:
```env
OPENAI_API_KEY=your_openai_api_key_here
VCS_HOME=/path/to/your/synopsys/vcs
WAVEKIT_PATH=/path/to/your/wavekit
```

### 3. Thực thi hệ thống
Chạy luồng pipeline đa tác tử để tự động sinh và kiểm thử RTL:
```bash
python main.py --spec ./spec/your_hardware_spec.txt --output ./output_rtl/
