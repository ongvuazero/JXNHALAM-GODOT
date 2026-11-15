<div align="center">

# JXNHALAM GODOT

**Dự án nghiên cứu và học hỏi: tái dựng cơ chế game 2D kiểu Võ Lâm Truyền Kỳ 1 bằng Godot 4**

*Godot 4 · GDScript · SPR/PAK · 2D Animation · Combat · Skill VFX · Lua*

**Trạng thái: Work in Progress — bản thử nghiệm kỹ thuật, chưa phải game hoàn chỉnh**

</div>

---

## 🎯 Mục tiêu

JXNHALAM GODOT được chia sẻ để mọi người **học hỏi, trao đổi kinh nghiệm và nghiên cứu kỹ thuật phát triển game 2D**. Dự án tập trung vào cách tổ chức mã nguồn trong Godot, đọc dữ liệu đồ họa SPR/PAK, xử lý hoạt ảnh nhiều hướng và tìm hiểu hệ thống kỹ năng nhiều tầng từ dữ liệu cấu hình và Lua.

Đây là dự án thực hành, thử nghiệm và đối chiếu hành vi — **không phải bản port chính thức, máy chủ phát hành hay phiên bản thay thế cho trò chơi gốc**.

## 🧩 Những gì đang được nghiên cứu

- **Godot 4 / GDScript:** cấu trúc scene, quản lý nhân vật, NPC, input và vòng lặp combat.
- **SPR/PAK:** giải mã sprite nhiều frame/nhiều hướng, vị trí frame và tra cứu tài nguyên từ client hợp lệ.
- **Animation 2D:** đứng, di chuyển, tấn công, hướng nhìn, đồng bộ frame và sự kiện.
- **Combat 10 môn phái:** dữ liệu kỹ năng và các màn thử nghiệm; độ hoàn thiện khác nhau giữa từng phái.
- **Skill 9x & VFX nhiều tầng:** `PreCast`, `Fly`, `TravelEnd`, `Hit`, sự kiện skill con từ Lua.
- **Missile:** bay thẳng, bám mục tiêu, đội hình nhiều viên, quỹ đạo đặc biệt và kiểm tra va chạm.
- **QA / Audit:** so sánh `skills.txt`, `missles.txt`, Lua với đường dẫn SPR; thống kê hiệu ứng thiếu hoặc đọc lỗi.

> **Lưu ý:** Một phần tốc độ, tầm đánh, kích thước, vị trí va chạm, đội hình và thời điểm phát VFX hiện là thông số **QA/ước lượng**, chưa được xác nhận tương đương client JX1 gốc. Một số kỹ năng vẫn thiếu hiệu ứng hoặc chưa đúng hành vi.

## 🛠️ Yêu cầu

- **Godot 4.6.1** (hoặc bản Godot 4 tương thích; môi trường đang phát triển là 4.6.1).
- Windows là môi trường thử nghiệm chính.
- Dữ liệu SPR/PAK **mà bạn có quyền sử dụng**, nếu muốn thử các hiệu ứng phụ thuộc client; không phải mọi tính năng đều hoạt động với dữ liệu mẫu có sẵn.

## 🚀 Chạy thử

1. Tải repository bằng **Code → Download ZIP** hoặc `git clone`.
2. Mở Godot → **Import** → chọn `project.godot` ở thư mục gốc.
3. Mở project, đợi Godot nhập tài nguyên, sau đó nhấn **F5**.
4. Nếu muốn thử tài nguyên client riêng, tạo `client_root.txt` từ `client_root.txt.example` và điền **đường dẫn local** đến bộ dữ liệu bạn có quyền dùng. Không commit file này.
5. Khi chạy, có thể dùng **P** để chọn nguồn dữ liệu PAK, **F10** xuất báo cáo SPR và **Tab** chuyển môn phái thử nghiệm.

### Phím điều khiển trong màn QA

| Thao tác | Phím / chuột |
|---|---|
| Di chuyển | Chuột trái |
| Chọn mục tiêu / đánh | Chuột phải |
| Đánh liên tục | Giữ `Space` |
| Chuyển môn phái | `Tab` |
| Chọn kỹ năng | Các ô kỹ năng trên giao diện |
| Bật / tắt thông tin debug | `D` |
| Kiểm tra VFX | `V` |
| Kiểm tra dữ liệu SPR | `F10` |
| Chọn thư mục PAK | `P` |
| Reset màn thử nghiệm | `R` |

*Các phím có thể thay đổi theo phiên bản và chế độ QA.*

## 📁 Cấu trúc repository

```text
JXNHALAM-GODOT/
├── project.godot       # Cấu hình project Godot
├── scenes/             # Scene game và màn thử nghiệm
├── scripts/            # Logic nhân vật, combat, animation, VFX, PAK/SPR
├── assets/             # Asset/atlas dùng trong project
├── data/               # JSON cấu hình phái, skill và dữ liệu QA
├── settings/           # Bảng cấu hình tham khảo của phiên bản đang nghiên cứu
├── ServerBaseline/     # Dữ liệu/server-script tham khảo, gồm Lua môn phái
├── tests/              # Bài kiểm tra kỹ thuật
├── tools/              # Công cụ kiểm tra, trích xuất và báo cáo
├── reports/            # Báo cáo đối chiếu kỹ thuật
└── client_root.txt.example
```

## 📚 Gợi ý học từ source

1. **Bắt đầu từ `scenes/main.tscn` và `scripts/Main.gd`** để hiểu gameplay loop và các luồng thử nghiệm.
2. Đọc **`scripts/Player.gd`** và các script combat để theo dõi quá trình chọn mục tiêu → phát chiêu → hồi chiêu.
3. Tìm hiểu **`scripts/JXSPRCodec.gd`, `scripts/ClientAssetResolver.gd`** để xem cơ chế xử lý SPR và tra cứu PAK.
4. Xem **`data/sects/`**, **`settings/skills.txt`**, **`settings/missles.txt`** và **`ServerBaseline/script/skill/*.lua`** để phân biệt skill mẹ, missile và sự kiện skill con.
5. Thử **`scripts/JXSectSkillPreview.gd`**, **`scripts/JXLuaEventVFX.gd`** và các module missile; đối chiếu kết quả bằng log và báo cáo F10.

Tên file/module có thể thay đổi khi dự án tiếp tục được tái cấu trúc.

## ⚠️ Tình trạng và giới hạn

- Dự án **đang phát triển**, có thể có lỗi cú pháp, hiệu năng, lệch sprite hoặc thiếu SPR tùy bộ dữ liệu.
- Nhiều môn phái đang dùng **màn thử nghiệm** và có thể dùng nhân vật mẫu thay cho đồ họa riêng của phái.
- Sát thương, va chạm và AI trong một số chế độ là **demo/QA**, không phải mô phỏng server gốc hoàn chỉnh.
- Tập tin Lua, cấu hình và SPR có thể thuộc các **phiên bản trò chơi khác nhau**; trùng skill ID không đủ chứng minh hiển thị đúng.
- Repository chưa cam kết tương thích mọi bộ PAK/SPR hoặc hoạt động ổn định ở tất cả các bản Godot 4.

## 🤝 Chia sẻ và đóng góp

Mọi người có thể **đọc source để học, thảo luận, báo lỗi và đề xuất cải tiến**. Khi gửi issue hoặc pull request, nên ghi rõ:

- Phiên bản Godot, môi trường chạy và commit đang dùng.
- Skill ID / tên kỹ năng, dữ liệu Lua hoặc bảng cấu hình liên quan.
- Ảnh hoặc video so sánh **kết quả mong đợi** và **kết quả thực tế**.
- Log Godot và báo cáo F10 nếu có; **không đăng bộ PAK bản quyền, khóa truy cập hoặc đường dẫn riêng tư**.

Ưu tiên các cải tiến có thể kiểm chứng từ dữ liệu nguồn, không tự gắn VFX của kỹ năng khác để che phần còn thiếu.

## ⚖️ Bản quyền và phạm vi sử dụng

Đây là dự án **nghiên cứu/học tập do cộng đồng thực hiện, không liên kết hoặc được chứng thực bởi chủ sở hữu Võ Lâm Truyền Kỳ / JX1**. Tên thương mại, hình ảnh, âm thanh, file SPR/PAK, mã nguồn hoặc dữ liệu của bên thứ ba (nếu có) vẫn thuộc quyền của chủ sở hữu tương ứng.

**Việc repository có thể xem công khai không đồng nghĩa với việc toàn bộ nội dung được cấp phép tự do tái sử dụng, phát hành hoặc thương mại hóa.** Hãy chỉ dùng/đóng góp nội dung mà bạn có quyền chia sẻ. Nếu phát hiện tập tin có vấn đề về quyền sử dụng, vui lòng tạo issue để cùng rà soát.

Chưa có giấy phép mã nguồn mở thống nhất được công bố cho toàn bộ repository; việc sao chép hoặc phân phối lại ngoài phạm vi pháp luật cho phép cần có sự đồng ý của chủ sở hữu quyền liên quan.

---

**JXNHALAM** — *Chia sẻ để học hỏi, cải tiến qua kiểm chứng và cùng phát triển kỹ năng làm game 2D.*
