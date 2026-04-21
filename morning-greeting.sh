#!/bin/bash
# 每天早上傳早安訊息給家族群組
# Taiwan 7:00am = UTC 23:00 (前一天)
# cron: 0 23 * * * /root/my-line-bot/morning-greeting.sh >> /tmp/morning.log 2>&1

source ~/.claude/channels/line/.env
GROUP_ID="C00187729030429695b93114aed6d5bab"
DATE=$(TZ=Asia/Taipei date '+%Y/%m/%d %A')
MEMORY=$(cat ~/.claude/channels/line/memory.json 2>/dev/null || echo '{}')
DATES=$(cat ~/.claude/channels/line/dates.json 2>/dev/null || echo '{"dates":[]}')

# 用 claude --print 生成早安訊息
MESSAGE=$(claude --print "你是小跳跳，請用可愛的口吻對爸爸媽媽說早安。
今天是台灣時間 ${DATE}。
記憶內容：${MEMORY}
重要日期：${DATES}
請生成一則簡短（50字以內）的早安訊息，可以提到今天有什麼特別的事或記憶裡的計畫。只輸出訊息本身，不要加任何說明。" 2>/dev/null)

if [ -z "$MESSAGE" ]; then
  MESSAGE="早安！爸爸媽媽今天也要加油喔 ☀️"
fi

curl -s -X POST https://api.line.me/v2/bot/message/push \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"to\": \"${GROUP_ID}\", \"messages\": [{\"type\": \"text\", \"text\": $(echo "$MESSAGE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}]}"

echo "$(date): morning greeting sent"
