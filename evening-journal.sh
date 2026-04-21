#!/bin/bash
# evening-journal.sh - 每晚推日記邀請
# cron: 30 13 * * * (UTC 13:30 = 台灣 21:30)

source ~/.claude/channels/line/.env

WEEKDAYS=("日" "一" "二" "三" "四" "五" "六")
DAY_OF_WEEK=$(TZ=Asia/Taipei date +%w)
WEEKDAY=${WEEKDAYS[$DAY_OF_WEEK]}
DATE=$(TZ=Asia/Taipei date '+%m/%d')

MESSAGES=(
  "今天（${DATE}，週${WEEKDAY}）過得怎麼樣？有什麼想記下來的嗎 📝"
  "一天快結束囉～今天有發生什麼有趣的事嗎 😊"
  "爸爸/媽媽，今天辛苦了 🌙 有什麼想跟小跳跳分享的嗎？"
  "今天印象最深刻的一件事是什麼呀？💭"
  "晚安前說說今天吧～開心的、辛苦的都可以告訴小跳跳 🥰"
)

# 隨機選一則
IDX=$((RANDOM % ${#MESSAGES[@]}))
MSG="${MESSAGES[$IDX]}"

curl -s -X POST https://api.line.me/v2/bot/message/push \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"to\": \"C00187729030429695b93114aed6d5bab\", \"messages\": [{\"type\": \"text\", \"text\": $(echo "$MSG" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}]}"

echo "$(date): evening journal prompt sent"
