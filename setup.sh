#!/bin/bash
# setup.sh — Cài đặt và quản lý OpenClaw trên macOS
#
# Cách dùng:
#   bash setup.sh                  → Setup lần đầu hoặc máy mới
#   bash setup.sh --update-token   → Chỉ update Telegram token
#   bash setup.sh --reset          → Xóa config cũ và setup lại từ đầu

set -e

OPENCLAW_DIR="$HOME/.openclaw"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "🦞 OpenClaw Setup Script"
echo "========================"
echo ""

# ─────────────────────────────────────────
# Option: --update-token
# ─────────────────────────────────────────
if [[ "$1" == "--update-token" ]]; then
  echo "🔄 Cập nhật Telegram token..."
  echo ""
  read -p "Telegram Bot Token mới: " NEW_TOKEN
  read -p "Telegram User ID (Enter để giữ nguyên): " NEW_USER_ID

  openclaw config set channels.telegram.botToken "$NEW_TOKEN"

  if [[ -n "$NEW_USER_ID" ]]; then
    openclaw config set channels.telegram.allowFrom "[\"$NEW_USER_ID\"]"
    openclaw config set commands.ownerAllowFrom "[\"telegram:$NEW_USER_ID\"]"
  fi

  echo ""
  echo "♻️  Restart gateway..."
  launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
  sleep 1
  launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist

  echo "✅ Token đã cập nhật và gateway đã restart"
  echo ""
  echo "Kiểm tra kết nối:"
  echo "  openclaw status --deep"
  exit 0
fi

# ─────────────────────────────────────────
# Option: --reset
# ─────────────────────────────────────────
if [[ "$1" == "--reset" ]]; then
  echo "⚠️  Reset sẽ xóa openclaw.json hiện tại."
  read -p "Bạn chắc chắn? (y/N): " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Hủy."
    exit 0
  fi
  rm -f "$OPENCLAW_DIR/openclaw.json"
  echo "✅ Đã xóa openclaw.json, tiếp tục setup..."
  echo ""
fi

# ─────────────────────────────────────────
# 1. Kiểm tra Node.js
# ─────────────────────────────────────────
if ! command -v node &> /dev/null; then
  echo "❌ Node.js chưa được cài. Tải tại: https://nodejs.org"
  exit 1
fi
echo "✅ Node.js $(node -v)"

# ─────────────────────────────────────────
# 2. Cài OpenClaw
# ─────────────────────────────────────────
if ! command -v openclaw &> /dev/null; then
  echo "📦 Đang cài OpenClaw..."
  npm install -g openclaw
  echo "✅ OpenClaw đã cài"
else
  echo "✅ OpenClaw $(openclaw --version 2>/dev/null || echo 'đã cài')"
fi

# ─────────────────────────────────────────
# 3. Tạo thư mục config
# ─────────────────────────────────────────
echo ""
echo "📁 Tạo thư mục cấu hình..."
mkdir -p "$OPENCLAW_DIR/agents/main"
mkdir -p "$OPENCLAW_DIR/workspace"

# ─────────────────────────────────────────
# 4. Copy BOOTSTRAP.md
# ─────────────────────────────────────────
echo "📝 Copy agent BOOTSTRAP.md..."
cp "$REPO_DIR/agents/main/BOOTSTRAP.md" "$OPENCLAW_DIR/agents/main/BOOTSTRAP.md"
echo "✅ BOOTSTRAP.md đã copy"

# ─────────────────────────────────────────
# 5. Tạo openclaw.json từ template
# ─────────────────────────────────────────
CONFIG_PATH="$OPENCLAW_DIR/openclaw.json"

if [ -f "$CONFIG_PATH" ]; then
  echo ""
  echo "⚠️  openclaw.json đã tồn tại."
  echo "   Để update token: bash setup.sh --update-token"
  echo "   Để setup lại từ đầu: bash setup.sh --reset"
else
  echo ""
  echo "⚙️  Tạo openclaw.json từ template..."
  echo ""

  read -p "Telegram Bot Token: " TELEGRAM_TOKEN
  while [[ -z "$TELEGRAM_TOKEN" ]]; do
    echo "❌ Token không được để trống."
    read -p "Telegram Bot Token: " TELEGRAM_TOKEN
  done

  read -p "Telegram User ID của bạn: " TELEGRAM_USER_ID
  while [[ -z "$TELEGRAM_USER_ID" ]]; do
    echo "❌ User ID không được để trống."
    read -p "Telegram User ID của bạn: " TELEGRAM_USER_ID
  done

  # Tạo random gateway token
  GATEWAY_TOKEN=$(openssl rand -hex 24)

  # Copy template và thay thế giá trị
  sed \
    -e "s/__REPLACE_WITH_TELEGRAM_BOT_TOKEN__/$TELEGRAM_TOKEN/g" \
    -e "s/__REPLACE_WITH_YOUR_TELEGRAM_USER_ID__/$TELEGRAM_USER_ID/g" \
    -e "s/__REPLACE_WITH_RANDOM_TOKEN__/$GATEWAY_TOKEN/g" \
    "$REPO_DIR/openclaw.template.json" > "$CONFIG_PATH"

  echo "✅ openclaw.json đã tạo"
fi

# ─────────────────────────────────────────
# 6. Cài LaunchAgent
# ─────────────────────────────────────────
echo ""
echo "🔧 Cài gateway LaunchAgent..."
openclaw gateway install 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
sleep 1
launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
echo "✅ Gateway đang chạy"

# ─────────────────────────────────────────
# 7. Đăng nhập OpenAI
# ─────────────────────────────────────────
echo ""
echo "🤖 Đăng nhập OpenAI (cần thiết để agent hoạt động)..."
echo ""

# Kiểm tra đã login chưa
OPENAI_STATUS=$(openclaw models status 2>/dev/null | grep -i "openai" || echo "")
if echo "$OPENAI_STATUS" | grep -qi "ok\|ready\|authenticated"; then
  echo "✅ OpenAI đã đăng nhập"
else
  echo "Cần đăng nhập OpenAI để agent có thể generate cover letter và xử lý lệnh."
  echo ""
  read -p "Nhấn Enter để mở trình duyệt đăng nhập OpenAI..." _

  # Chạy configure chỉ phần OpenAI login
  openclaw configure 2>/dev/null || true

  echo ""
  echo "✅ Nếu đăng nhập thành công, gateway sẽ tự nhận token."

  # Restart gateway để apply auth mới
  launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
  sleep 1
  launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist 2>/dev/null || true
fi

# ─────────────────────────────────────────
# 8. Xong
# ─────────────────────────────────────────
echo ""
echo "🎉 Setup hoàn tất!"
echo ""
echo "Bước tiếp theo:"
echo ""
echo "  1. Mở Chrome với remote debugging:"
echo "     /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \\"
echo "       --remote-debugging-port=9222 \\"
echo "       --user-data-dir=/tmp/openclaw-chrome \\"
echo "       --no-first-run --no-default-browser-check \\"
echo "       --disable-background-mode &"
echo ""
echo "  2. Đăng nhập Upwork trong Chrome đó (chỉ cần làm 1 lần)"
echo ""
echo "  3. Kiểm tra kết nối:"
echo "     openclaw status --deep"
echo ""
echo "  4. Nhắn /apply <job_id> qua Telegram bot của bạn"
echo ""
echo "Lệnh hữu ích:"
echo "  bash setup.sh --update-token   → Cập nhật Telegram token"
echo "  bash setup.sh --reset          → Setup lại từ đầu"
echo "  openclaw logs --follow         → Xem log realtime"
echo "  openclaw models status         → Kiểm tra OpenAI auth"