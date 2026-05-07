#!/bin/bash
# 每天早上傳早安訊息給家族群組
# Taiwan 7:00am = UTC 23:00 (前一天)
# cron: 0 23 * * * /root/my-line-bot/morning-greeting.sh >> /tmp/morning.log 2>&1

source ~/.claude/channels/line/.env
GROUP_ID="C00187729030429695b93114aed6d5bab"

# 算今日日期 + 中文星期（avoid LLM 從英文 weekday 翻錯）
TODAY=$(TZ=Asia/Taipei date '+%Y-%m-%d')
TODAY_DISPLAY=$(TZ=Asia/Taipei date '+%Y/%m/%d')
WEEKDAY_NUM=$(TZ=Asia/Taipei date '+%u')
case $WEEKDAY_NUM in
  1) WEEKDAY="週一";;
  2) WEEKDAY="週二";;
  3) WEEKDAY="週三";;
  4) WEEKDAY="週四";;
  5) WEEKDAY="週五";;
  6) WEEKDAY="週六";;
  7) WEEKDAY="週日";;
esac

# 背景記憶（家人偏好、長期計畫，僅供參考、不當成今日 trigger）
MEMORY=$(cat ~/.claude/channels/line/memory.json 2>/dev/null || echo '{}')

# 在 bash 階段就 filter 今天的 events，不要把整個 events.json 丟給 LLM 自己算
EVENTS_FILE="/root/my-line-bot/events.json"
[ ! -f "$EVENTS_FILE" ] && EVENTS_FILE="$(dirname "$0")/events.json"
TODAYS_EVENTS=$(jq -r --arg t "$TODAY" \
  '[.events[]? | select(.date==$t) | .title] | if length==0 then "（無）" else join("；") end' \
  "$EVENTS_FILE" 2>/dev/null)
[ -z "$TODAYS_EVENTS" ] && TODAYS_EVENTS="（無）"

# 取得桃園天氣（wttr.in，不需要 API key）
WEATHER=$(curl -s --max-time 5 "wttr.in/桃園?format=%C，%t，體感%f，濕度%h" 2>/dev/null || echo "")

# 用 claude --print 生成早安訊息
MESSAGE=$(claude --print "你是小跳跳，請用可愛的口吻對爸爸媽媽說早安。

今天日期：${TODAY_DISPLAY}（${WEEKDAY}）
今天桃園天氣：${WEATHER}
今天的行程（只能提這些；如果是「（無）」就完全不要提行程）：${TODAYS_EVENTS}
背景記憶（家人偏好和長期計畫，僅供參考，不要當成今日 trigger，不要說『今晚／明天／昨天』）：${MEMORY}

規則（必須遵守）：
1. 『今晚／明天／昨天』這類詞，只能用於「今天的行程」明確列出的事件，不要從背景記憶或自己腦補
2. 如果「今天的行程」是「（無）」，訊息就不要提任何行程，只講星期、天氣、穿衣
3. 訊息 60 字以內，必須包含星期幾、天氣、穿衣建議
4. 只輸出訊息本身，不要加任何說明" 2>/dev/null)

if [ -z "$MESSAGE" ]; then
  MESSAGE="早安！爸爸媽媽今天也要加油喔 ☀️"
fi

curl -s -X POST https://api.line.me/v2/bot/message/push \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"to\": \"${GROUP_ID}\", \"messages\": [{\"type\": \"text\", \"text\": $(echo "$MESSAGE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}]}"

echo "$(date): morning greeting sent"
