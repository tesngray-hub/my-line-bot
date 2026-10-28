#!/bin/bash
# Usage: add-event.sh "2026-05-01" "看牙醫" "爸爸"
DATE="$1"
TITLE="$2"
BY="${3:-小跳跳}"

# 10/28 大修 ③：單一寫入口（檔鎖＋pull --ff-only＋原子寫＋commit/push）
python3 /root/family-bot/family_events.py add "$DATE" "$TITLE" --by "$BY" || exit 1

# 同步到 Google Calendar
curl -s "https://script.google.com/macros/s/AKfycbyV67BTrcxGWj6U8168zSWRVUp-8gkoyr9kEDSKeKkN8Xe3BlpiKvl9zGgdWBDqin-L/exec?date=${DATE}&title=${TITLE}&by=${BY}"
