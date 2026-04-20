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

# 自動更新 LINE webhook
source ~/.claude/channels/line/.env
curl -s -X PUT https://api.line.me/v2/bot/channel/webhook/endpoint \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"webhookEndpoint\": \"${URL}/webhook\"}"
echo ""
echo "Webhook 已更新: ${URL}/webhook"

# 在 screen session 裡啟動 claude（有 TTY）
screen -dmS linebot bash -c "cd /root/my-line-bot && claude --dangerously-load-development-channels server:line-channel"
echo "機器人已在 screen session 'linebot' 啟動"
