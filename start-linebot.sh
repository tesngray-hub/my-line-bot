#!/bin/bash

# 清除舊的 session 和殘留的 bun 進程
pkill cloudflared 2>/dev/null || true
pkill -f "python3 -m http.server 3457" 2>/dev/null || true
tmux kill-session -t linebot 2>/dev/null || true
pkill -f "bun.*server.ts" 2>/dev/null || true
sleep 2

# 啟動靜態圖片伺服器（port 3457）
python3 -m http.server 3457 --directory /root/.claude/channels/line/inbox/ > /tmp/fileserver.log 2>&1 &

# Use named tunnel (kgi-tunnel.service routes family.weixuninvest.com → 3456)
URL="https://family.weixuninvest.com"
IMG_HOST=""
echo "$(date) using named tunnel: $URL"
echo "$URL" > /tmp/named_tunnel_url.txt

# 等 cloudflared 完全就緒
sleep 5

# 啟動 claude，失敗自動重試（最多 3 次）
CLAUDE_STARTED=false
for attempt in 1 2 3; do
  echo "嘗試啟動 claude（第 ${attempt} 次）..."
  tmux kill-session -t linebot 2>/dev/null || true
  sleep 2

  # 建立 tmux session 後用 send-keys 執行（PTY 正確連接，不需要 SSH）
  tmux new-session -d -s linebot -x 220 -y 50
  sleep 1
  tmux send-keys -t linebot "cd /root/my-line-bot && claude --dangerously-load-development-channels server:line-channel" Enter
  # 自動確認 "I am using this for local development" 提示
  sleep 4
  tmux send-keys -t linebot "1" Enter

  # 等待 port 3456 就緒（最多 90 秒）
  echo "等待 port 3456..."
  for i in $(seq 1 90); do
    if ss -tlnp | grep -q 3456; then
      echo "Port 3456 就緒（${i}秒）"
      CLAUDE_STARTED=true
      break
    fi
    # 如果 tmux session 死掉了，提早放棄這次嘗試
    if ! tmux has-session -t linebot 2>/dev/null; then
      echo "tmux session 意外結束，重試..."
      break
    fi
    sleep 1
  done

  if [ "$CLAUDE_STARTED" = true ]; then
    break
  fi
  echo "第 ${attempt} 次啟動失敗"
done

if [ "$CLAUDE_STARTED" = false ]; then
  echo "錯誤：claude 三次啟動均失敗，退出讓 systemd 重啟"
  exit 1
fi

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

# 通知群組 bot 重新上線
source ~/.claude/channels/line/.env
curl -s -X POST https://api.line.me/v2/bot/message/push \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"to": "C00187729030429695b93114aed6d5bab", "messages": [{"type": "text", "text": "小跳跳重新上線了！🔄✨\n如果有訊息沒收到，可以重新傳一次喔～"}]}' > /dev/null

# Claude 5 分鐘崩 → 內部重啟 tmux，不讓 systemd 整個重啟
while true; do
  if ! tmux has-session -t linebot 2>/dev/null; then
    echo "$(date) tmux died, restarting Claude inside loop"
    tmux new-session -d -s linebot -x 220 -y 50
    sleep 1
    tmux send-keys -t linebot "cd /root/my-line-bot && claude --dangerously-load-development-channels server:line-channel" Enter
    sleep 4
    tmux send-keys -t linebot "1" Enter
    # 等 port 3456 起來
    for i in $(seq 1 60); do
      ss -tlnp | grep -q 3456 && break
      sleep 1
    done
    if ss -tlnp | grep -q 3456; then
      echo "$(date) bun re-up after Claude crash"
    else
      echo "$(date) bun failed to restart, exiting for systemd"
      exit 1
    fi
  fi
  sleep 10
done
