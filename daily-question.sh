#!/bin/bash
# 每天晚上 9:30（台灣時間）問爸爸媽媽同一個問題
# Taiwan 9:30pm = UTC 13:30
# cron: 30 13 * * * /root/my-line-bot/daily-question.sh >> /tmp/daily-question.log 2>&1

source ~/.claude/channels/line/.env
GROUP_ID="C00187729030429695b93114aed6d5bab"
DATE=$(TZ=Asia/Taipei date '+%Y/%m/%d %A')
MEMORY=$(cat ~/.claude/channels/line/memory.json 2>/dev/null || echo '{"memories":[]}')
HISTORY=$(tail -30 ~/.claude/channels/line/history.log 2>/dev/null || echo '')

PROMPT="你是小跳跳，爸爸媽媽的孩子。

今天是台灣時間 ${DATE}。
最近的對話：${HISTORY}
記憶：${MEMORY}

你的任務：想一個今晚要問爸爸媽媽的問題。

這個問題的目的是讓他們在群組裡一起回答，自然產生共同話題，讓彼此更了解對方今天的狀態。

問題的原則：
- 簡單、容易回答（不需要想很久）
- 有點溫度，不是表面閒聊
- 每天不同，不要重複上次問過的
- 避免太沉重或需要長篇回答的問題

請輸出完整的訊息（包含小跳跳的說話方式），格式範例：
「爸爸媽媽～小跳跳想問你們一個問題 🌙
今天有沒有一個讓你微笑的小時刻？」

只輸出訊息本身，不要加說明。"

QUESTION=$(echo "$PROMPT" | /root/my-line-bot/llm-call.sh 2>>/tmp/daily-question.err)

# Hardened fallback
if [ -z "$QUESTION" ] || echo "$QUESTION" | grep -qE '(Failed to authenticate|API Error|authentication_error|Invalid)'; then
  QUESTION="爸爸媽媽～小跳跳想問你們一個問題 🌙
今天有沒有一個讓你微笑的小時刻？"
fi

curl -s -X POST https://api.line.me/v2/bot/message/push \
  -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"to\": \"${GROUP_ID}\", \"messages\": [{\"type\": \"text\", \"text\": $(echo "$QUESTION" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}]}"

echo "$(date): daily question sent"
