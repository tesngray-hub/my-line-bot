#!/bin/bash

# 清除舊的 session 和殘留的 bun 進程
pkill cloudflared 2>/dev/null || true
pkill -f "python3 -m http.server 3457" 2>/dev/null || true
tmux kill-session -t linebot 2>/dev/null || true
pkill -f "bun.*server.ts" 2>/dev/null || true
sleep 2

# 啟動靜態圖片伺服器（port 3457）
python3 -m http.server 3457 --directory /root/.claude/channels/line/inbox/ > /tmp/fileserver.log 2>&1 &

# 啟動兩條 cloudflared tunnel
cloudflared tunnel --url http://localhost:3456 --no-autoupdate > /tmp/tunnel.log 2>&1 &
cloudflared tunnel --url http://localhost:3457 --no-autoupdate > /tmp/tunnel2.log 2>&1 &

# 等待 webhook tunnel URL（最多 30 秒）
echo "等待 tunnel URL..."
for i in $(seq 1 30); do
  URL=$(grep -o 'https://[^[:space:]]*trycloudflare.com' /tmp/tunnel.log | head -1)
  if [ -n "$URL" ]; then
    echo "Tunnel URL: $URL"
    break
  fi
  sleep 1
done

if [ -z "$URL" ]; then
  echo "錯誤：無法取得 tunnel URL"
  exit 1
fi

# 等待 image host tunnel URL（最多 30 秒）
echo "等待 image host tunnel URL..."
for i in $(seq 1 30); do
  IMG_HOST=$(grep -o 'https://[^[:space:]]*trycloudflare.com' /tmp/tunnel2.log | head -1)
  if [ -n "$IMG_HOST" ]; then
    echo "Image host URL: $IMG_HOST"
    echo "$IMG_HOST" > /tmp/image_host_url.txt
    break
  fi
  sleep 1
done

if [ -z "$IMG_HOST" ]; then
  echo "警告：無法取得 image host URL，產圖功能可能受影響"
fi

# 等 cloudflared 完全就緒
sleep 5

# 用 SSH 建立真正的 TTY 啟動 claude
tmux kill-session -t linebot 2>/dev/null || true
tmux new-session -d -s linebot "ssh -i /root/.ssh/bot_key -o StrictHostKeyChecking=no -t root@localhost 'cd /root/my-line-bot && claude --dangerously-load-development-channels server:line-channel'"
echo "機器人已啟動，等待 port 3456（最多 120 秒）..."

# 等待 port 3456 就緒（最多 120 秒）
for i in $(seq 1 120); do
  if ss -tlnp | grep -q 3456; then
    echo "Port 3456 就緒（${i}秒）"
    break
  fi
  sleep 1
done

# 等 cloudflared 完全穩定
sleep 10

# 更新 LINE webhook
source ~/.claude/channels/line/.env
RESULT=$(curl -s -X PUT https://api.line.me/v2/bot/channel/webhook/endpoint \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"endpoint\": \"${URL}/webhook\"}")
echo "Webhook 更新結果: $RESULT"
echo "Webhook URL: ${URL}/webhook"

# 持續監控 tmux session，掛掉就退出讓 systemd 重啟
while tmux has-session -t linebot 2>/dev/null; do
  sleep 10
done
echo "tmux session 結束，服務退出"
