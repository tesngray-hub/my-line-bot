#!/bin/bash
# 每天檢查重要日期，提前提醒
# Taiwan 8:00am = UTC 0:00
# cron: 0 0 * * * /root/my-line-bot/date-reminder.sh >> /tmp/date-reminder.log 2>&1

DATES_FILE=~/.claude/channels/line/dates.json
GROUP_ID="C00187729030429695b93114aed6d5bab"

if [ ! -f "$DATES_FILE" ]; then
  echo "$(date): dates.json not found, skipping"
  exit 0
fi

python3 << PYEOF
import json, datetime, subprocess, re, os

# 直接讀 .env 取得 token
env_path = os.path.expanduser('~/.claude/channels/line/.env')
token = ''
with open(env_path) as ef:
    for line in ef:
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line.strip())
        if m:
            token = m.group(1).strip().strip("'\"")
            break

group_id = '$GROUP_ID'
dates_file = '$DATES_FILE'

with open(dates_file) as f:
    data = json.load(f)

today = datetime.date.today() + datetime.timedelta(hours=8)  # UTC+8

for item in data.get('dates', []):
    label = item.get('label', '')
    date_str = item.get('date', '')
    days_before = item.get('remind_days_before', 1)

    try:
        if len(date_str) == 5:  # MM-DD 格式，每年重複
            target = datetime.date(today.year, int(date_str[:2]), int(date_str[3:]))
            if target < today:
                target = datetime.date(today.year + 1, int(date_str[:2]), int(date_str[3:]))
        else:
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

    payload = json.dumps({'to': group_id, 'messages': [{'type': 'text', 'text': msg}]}, ensure_ascii=False)
    subprocess.run(['curl', '-s', '-X', 'POST',
        'https://api.line.me/v2/bot/message/push',
        '-H', f'Authorization: Bearer {token}',
        '-H', 'Content-Type: application/json',
        '-d', payload])
    print(f'Reminded: {label} in {delta} days')
PYEOF

echo "$(date): date check done"
