# openclaw-config

Config repository cho OpenClaw — automation agent kết nối Telegram bot với browser automation.

## Cấu trúc repo

```
openclaw-config/
├── .gitignore                  # Loại trừ secrets và runtime files
├── openclaw.template.json      # Config template (không có secrets)
├── setup.sh                    # Script tự động setup — macOS/Linux
├── setup.ps1                   # Script tự động setup — Windows
├── agents/
│   └── main/
│       └── BOOTSTRAP.md        # Skill /apply Upwork
└── README.md
```

---

## Cài đặt máy mới

### Yêu cầu
- Node.js 18+
- Google Chrome
- macOS hoặc Windows 10/11

### macOS

```bash
git clone <repo_url> openclaw-config
cd openclaw-config
chmod +x setup.sh
bash setup.sh
```

### Windows

Mở PowerShell với quyền Administrator:

```powershell
git clone <repo_url> openclaw-config
cd openclaw-config
powershell -ExecutionPolicy Bypass -File setup.ps1
```

> Nếu muốn service ổn định hơn trên Windows, cài thêm [NSSM](https://nssm.cc/download) trước khi chạy script. Script sẽ tự phát hiện và dùng NSSM nếu có.

### Script sẽ hỏi:
- **Telegram Bot Token** — lấy từ [@BotFather](https://t.me/BotFather)
- **Telegram User ID** — lấy từ [@userinfobot](https://t.me/userinfobot)
- **OpenAI email** — tài khoản dùng để login OpenAI Codex

---

## Sau khi setup xong

### macOS — Chạy Chrome với remote debugging:
```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir=/tmp/openclaw-chrome \
  --no-first-run --no-default-browser-check \
  --disable-background-mode &
```

### Windows — Chạy Chrome với remote debugging:
```powershell
powershell -File start-chrome.ps1
```
(File `start-chrome.ps1` được tự động tạo bởi `setup.ps1`)

Sau đó **đăng nhập Upwork** trong Chrome vừa mở (chỉ cần làm 1 lần, session được lưu lại).

### Kiểm tra:
```bash
openclaw status --deep
```
Telegram channel phải hiện `OK`.

### Test:
Nhắn qua Telegram bot:
```
/apply 022057683405563489518 jobType=Fixed
```
> Thay `jobType` thành `Hourly` khi test flow Hourly.

---

## Skill: /apply

Cú pháp gửi cho agent (qua Telegram **hoặc API**):

```
/apply <job_id_or_url> jobType=<Hourly|Fixed>

COVER_LETTER:
<cover_letter_text>
```

`jobType` là bắt buộc (không phân biệt hoa thường) để agent biết phải dùng flow Hourly hay Fixed khi apply.

Lệnh tự động:
1. Mở trang apply Upwork
2. Đọc job description
3. Dán đúng cover letter do người dùng cung cấp (không tự viết)
4. Điền form theo flow tương ứng `jobType` (chi tiết trong `agents/main/BOOTSTRAP.md`)
5. Submit
6. Báo kết quả về Telegram

---

## Đồng bộ BOOTSTRAP và restart Gateway

Khi chỉnh `agents/main/BOOTSTRAP.md`, luôn copy sang **cả hai** vị trí trên máy đang chạy gateway:

```bash
cp agents/main/BOOTSTRAP.md ~/.openclaw/agents/main/BOOTSTRAP.md
cp agents/main/BOOTSTRAP.md ~/.openclaw/workspace/BOOTSTRAP.md
```

Sau đó restart Gateway để agent nạp skill mới:

```bash
launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist
launchctl load  ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```

Xác minh nhanh:

```bash
diff agents/main/BOOTSTRAP.md ~/.openclaw/agents/main/BOOTSTRAP.md
diff agents/main/BOOTSTRAP.md ~/.openclaw/workspace/BOOTSTRAP.md
```

### Xóa session cũ của agent (nếu cần)

Nếu gateway vẫn giữ session cũ sau khi cập nhật BOOTSTRAP, xóa file session rồi để agent tạo lại:

```bash
rm -f ~/.openclaw/agents/main/sessions/sessions.json
```

### “Prime” session auto-apply

Sau khi restart, gửi một lệnh mở đầu để agent hiểu vai trò trước khi nhận `/apply` (ví dụ session key `agent:main:auto-apply`):

```bash
openclaw agent --agent main --session-key agent:main:auto-apply \
  --message "Bạn đang chạy local để xử lý /apply Upwork như trong BOOTSTRAP. Khi nhận /apply <job>, hãy làm theo hướng dẫn." \
  --json
```

Từ lần tiếp theo chỉ cần `/apply <job_id>` (qua Telegram hoặc API tùy bạn).

---

## Thêm skill mới

Sửa file `agents/main/BOOTSTRAP.md`, thêm section mô tả lệnh mới, rồi:

### macOS:
```bash
cp agents/main/BOOTSTRAP.md ~/.openclaw/agents/main/BOOTSTRAP.md
launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist
launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```

### Windows:
```powershell
Copy-Item agents\main\BOOTSTRAP.md $env:USERPROFILE\.openclaw\agents\main\BOOTSTRAP.md -Force
Restart-ScheduledTask -TaskName "OpenClawGateway"
# hoặc nếu dùng NSSM:
nssm restart OpenClawGateway
```

---

## Troubleshooting

### Bot không reply:
```bash
openclaw status --deep
openclaw logs --follow
```

### Muốn xem log chi tiết

- `openclaw logs --follow` → tương đương `tail -f` (Gateway định dạng sẵn)
- Hoặc trực tiếp: `tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log`

### Pairing / scope upgrade bị chặn

Khi thấy lỗi `pairing required` hoặc `scope upgrade pending approval`, mở Control UI hoặc chạy:

```bash
openclaw pairing approve --device <device_id>
```

Device ID xuất hiện trong log Gateway (`security audit: device access upgrade requested`). Approve một lần là thiết bị đó có thể gọi gateway về sau.

### Port 9222 conflict:

macOS:
```bash
lsof -ti :9222 | xargs kill -9
rm -rf /tmp/openclaw-chrome
```

Windows:
```powershell
Stop-Process -Id (Get-NetTCPConnection -LocalPort 9222).OwningProcess -Force
Remove-Item -Recurse -Force $env:TEMP\openclaw-chrome
```

### Upwork không đăng nhập:
Chrome profile bị xóa → đăng nhập lại thủ công.

### Reset hoàn toàn:

macOS:
```bash
rm ~/.openclaw/openclaw.json
bash setup.sh
```

Windows:
```powershell
Remove-Item $env:USERPROFILE\.openclaw\openclaw.json
powershell -ExecutionPolicy Bypass -File setup.ps1
```

---

## Secrets — KHÔNG bao giờ commit

| File | Lý do |
|------|-------|
| `openclaw.json` | Chứa bot token, gateway token |
| `credentials/` | API keys |
| `identity/` | Device identity gắn với máy |
| `telegram/` | Session Telegram |
| `*.sqlite` | Database runtime |
