#!/bin/bash
# 每週把超過 30 天的 events 移到 archive，避免 events.json 持續長大、
# 也避免舊事件 (e.g. 已經過完的卡內基課程) 還留在 active list 干擾 LLM。
#
# 安裝方式（在 bot server 上）:
#   crontab -e
#   加入: 0 0 * * 0 /root/my-line-bot/archive-old-events.sh >> /tmp/archive.log 2>&1
#   (每週日凌晨執行)

set -e

EVENTS_FILE="/root/my-line-bot/events.json"
ARCHIVE_FILE="/root/my-line-bot/events-archive.json"
[ ! -f "$EVENTS_FILE" ] && EVENTS_FILE="$(dirname "$0")/events.json"
[ ! -f "$ARCHIVE_FILE" ] && ARCHIVE_FILE="$(dirname "$0")/events-archive.json"

# 30 天前的日期 (GNU date / BSD date 兼容)
CUTOFF=$(TZ=Asia/Taipei date -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || \
         TZ=Asia/Taipei date -v-30d '+%Y-%m-%d')

# 初始化 archive 檔（不存在時）
[ ! -f "$ARCHIVE_FILE" ] && echo '{"events":[]}' > "$ARCHIVE_FILE"

# 拆分: keep = 30 天內 + 未來、archive = 超過 30 天
NEW_KEEP=$(jq --arg cutoff "$CUTOFF" '{events: [.events[] | select(.date >= $cutoff)]}' "$EVENTS_FILE")
NEW_ARCHIVED=$(jq --arg cutoff "$CUTOFF" '[.events[] | select(.date < $cutoff)]' "$EVENTS_FILE")

# 合併到既有 archive
MERGED_ARCHIVE=$(jq --argjson new "$NEW_ARCHIVED" '.events += $new' "$ARCHIVE_FILE")

# 寫回
echo "$NEW_KEEP" > "$EVENTS_FILE"
echo "$MERGED_ARCHIVE" > "$ARCHIVE_FILE"

# git commit (沿用 add-event.sh 的 pattern)
cd /root/my-line-bot 2>/dev/null || cd "$(dirname "$0")"
if git rev-parse --git-dir >/dev/null 2>&1; then
  git pull --rebase --autostash 2>/dev/null || true
  git add events.json events-archive.json
  if git diff --cached --quiet; then
    echo "$(date): no events older than $CUTOFF to archive"
  else
    git commit -m "Archive events older than $CUTOFF"
    git push 2>/dev/null || true
    echo "$(date): archived events older than $CUTOFF"
  fi
fi
