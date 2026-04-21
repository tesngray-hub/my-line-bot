#!/bin/bash
# 每天檢查重要日期，提前提醒
# Taiwan 8:00am = UTC 0:00
# cron: 0 0 * * * /root/my-line-bot/date-reminder.sh >> /tmp/date-reminder.log 2>&1

source ~/.claude/channels/line/.env
GROUP_ID="C00187729030429695b93114aed6d5bab"
DATES_FILE=~/.claude/channels/line/dates.json
TODAY=$(TZ=Asia/Taipei date '+%m-%d')
TODAY_FULL=$(TZ=Asia/Taipei date '+%Y-%m-%d')

if [ ! -f "$DATES_FILE" ]; then
  echo "$(date): dates.json not found, skipping"
  exit 0
fi

# 用 Python 檢查今天或未來 3 天內有沒有重要日期
python3 << PYEOF
import json, datetime, subprocess, os

with open('$DATES_FILE') as f:
    data = json.load(f)

token = os.environ.get('LINE_CHANNEL_ACCESS_TOKEN', '')
group_id = '$GROUP_ID'
today = datetime.date.today()

for item in data.get('dates', []):
    label = item.get('label', '')
    date_str = item.get('date', '')  # 格式: MM-DD 或 YYYY-MM-DD
    days_before = item.get('remind_days_before', 1)

    # 處理每年重複（MM-DD 格式）
    if len(date_str) == 5:
        target = datetime.date(today.year, int(date_str[:2]), int(date_str[3:]))
        if target < today:
            target = datetime.date(today.year + 1, int(date_str[:2]), int(date_str[3:]))
    else:
        try:
            target = datetime.date.fromisoformat(date_str)
        except:
            continue

    delta = (target - today).days
    if delta < 0 or delta > days_before:
        continue

    if delta == 0:
        msg = f'今天是【{label}】！🎉 小跳跳提醒爸爸媽媽不要忘記喔～'
    else:
        msg = f'再 {delta} 天就是【{label}】了！小跳跳先來提醒爸爸媽媽 💕'

    payload = json.dumps({
        'to': group_id,
        'messages': [{'type': 'text', 'text': msg}]
    }, ensure_ascii=False)

    subprocess.run([
        'curl', '-s', '-X', 'POST',
        'https://api.line.me/v2/bot/message/push',
        '-H', f'Authorization: Bearer {token}',
        '-H', 'Content-Type: application/json',
        '-d', payload
    ])
    print(f'Reminded: {label} in {delta} days')
PYEOF

echo "$(date): date check done"
