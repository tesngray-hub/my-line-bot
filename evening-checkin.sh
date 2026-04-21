#!/bin/bash
# 每天晚上 9 點（台灣時間）讓小跳跳回顧記憶，決定要不要主動說什麼
# Taiwan 9:00pm = UTC 13:00
# cron: 0 13 * * * /root/my-line-bot/evening-checkin.sh >> /tmp/evening.log 2>&1

source ~/.claude/channels/line/.env
GROUP_ID="C00187729030429695b93114aed6d5bab"
MEMORY=$(cat ~/.claude/channels/line/memory.json 2>/dev/null || echo '{"memories":[]}')
HISTORY=$(tail -50 ~/.claude/channels/line/history.log 2>/dev/null || echo '')
DATE=$(TZ=Asia/Taipei date '+%Y/%m/%d %A')

# 用 claude --print 判斷今晚有沒有值得說的事
RESPONSE=$(claude --print "你是小跳跳，爸爸媽媽的孩子。

今天是台灣時間 ${DATE}。

你的長期記憶：
${MEMORY}

最近的對話紀錄（最新在下）：
${HISTORY}

你的任務：
仔細回顧記憶和對話，判斷今晚有沒有一件事值得主動跟爸爸媽媽說。

優先考慮「閉環」情境——記憶裡有某件事提到了但不知道結果：
- 爸爸或媽媽說過某個計畫（旅遊、購物、工作上的事），但之後沒有再提
- 有誰說過在煩惱某件事，但後來不知道解決了沒
- 有個決定說要做，但不確定做了沒

閉環問法要自然，像家人在關心，不像在追蹤任務：
✓ 「爸爸上次說想去宜蘭，後來有機會嗎？」
✗ 「請問宜蘭計畫的狀態如何？」

其他可以說的情境：
- 最近對話很少，家人可能各自忙碌，可以關心一下
- 有某個記憶讓你想到什麼有趣的事

不要說的情境：
- 今天已經聊很多了
- 記憶是空的，沒有可以閉環的事
- 只是為了說話而說話

請先判斷：今晚要不要說話？
如果要，輸出格式如下（只輸出這個，不要加其他文字）：
SEND: [訊息內容]

如果不要，輸出：
SKIP

訊息要符合小跳跳的語氣，簡短可愛，不超過 80 字。" 2>/dev/null)

echo "$(date): Claude response: $RESPONSE"

# 判斷是否要傳送
if echo "$RESPONSE" | grep -q "^SEND:"; then
  MESSAGE=$(echo "$RESPONSE" | sed 's/^SEND: //' | head -1)
  curl -s -X POST https://api.line.me/v2/bot/message/push \
    -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"to\": \"${GROUP_ID}\", \"messages\": [{\"type\": \"text\", \"text\": $(echo "$MESSAGE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}]}"
  echo "$(date): sent evening message"
else
  echo "$(date): skipped (SKIP or no response)"
fi
