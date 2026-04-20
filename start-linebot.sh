#!/bin/bash

# 清除舊的 session
pkill cloudflared 2>/dev/null || true
screen -S linebot -X quit 2>/dev/null || true
sleep 1

# 啟動 cloudflared tunnel
cloudflared tunnel --url http://localhost:3456 --no-autoupdate > /tmp/tunnel.log 2>&1 &

# 等待 URL（最多 30 秒）
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

# 啟動 claude（用空行觸發初始化，sleep infinity 保持 stdin 開啟）
cd /root/my-line-bot
(echo ""; sleep infinity) | claude --dangerously-load-development-channels server:line-channel &
CLAUDE_PID=$!
echo "機器人已啟動 (PID: $CLAUDE_PID)，等待 port 3456..."

# 等待 port 3456 就緒（最多 30 秒）
for i in $(seq 1 30); do
  if ss -tlnp | grep -q 3456; then
    echo "Port 3456 就緒"
    break
  fi
  sleep 1
done

# 更新 LINE webhook
source ~/.claude/channels/line/.env
RESULT=$(curl -s -X PUT https://api.line.me/v2/bot/channel/webhook/endpoint \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"endpoint\": \"${URL}/webhook\"}")
echo "Webhook 更新結果: $RESULT"
echo "Webhook URL: ${URL}/webhook"

# 保持腳本運行（監控 claude 程序）
wait $CLAUDE_PID
echo "Claude 已退出，服務結束"
