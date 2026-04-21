#!/bin/bash
# 每天檢查重要日期，提前提醒
# Taiwan 8:00am = UTC 0:00
# cron: 0 0 * * * /root/my-line-bot/date-reminder.sh >> /tmp/date-reminder.log 2>&1

python3 << 'PYEOF'
import json, datetime, subprocess, re, os

env_path = os.path.expanduser('~/.claude/channels/line/.env')
token = ''
with open(env_path) as ef:
    for line in ef:
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line.strip())
        if m:
            token = m.group(1).strip().strip("'\"")
            break

# 台灣時間（UTC+8）
today = (datetime.datetime.utcnow() + datetime.timedelta(hours=8)).date()

dates_file = os.path.expanduser('~/.claude/channels/line/dates.json')
if not os.path.exists(dates_file):
    print('dates.json not found, skipping')
    exit(0)

with open(dates_file) as f:
    data = json.load(f)

group_id = 'C00187729030429695b93114aed6d5bab'

for item in data.get('dates', []):
    label = item.get('label', '')
    date_str = item.get('date', '')
    days_before = item.get('remind_days_before', 3)

    try:
        if len(date_str) == 5:  # MM-DD 每年重複
            m2, d = int(date_str[:2]), int(date_str[3:])
            target = datetime.date(today.year, m2, d)
            if target < today:
                target = datetime.date(today.year + 1, m2, d)
        else:
            target = datetime.date.fromisoformat(date_str)
    except Exception as e:
        print(f'Skip {label}: {e}')
        continue

    delta = (target - today).days
    if delta not in (0, days_before):
        continue

    if delta == 0:
        emoji = '🎂' if '生日' in label else '🎊'
        msg = f'{emoji} 今天是【{label}】！\n小跳跳提醒爸爸媽媽不要忘記喔～'
    else:
        emoji = '🎂' if '生日' in label else '💕'
        msg = f'{emoji} 再 {delta} 天就是【{label}】了！\n爸爸媽媽記得提早準備喔～'

    payload = json.dumps({
        'to': group_id,
        'messages': [{'type': 'text', 'text': msg}]
    }, ensure_ascii=False)

    r = subprocess.run(['curl', '-s', '-X', 'POST',
        'https://api.line.me/v2/bot/message/push',
        '-H', f'Authorization: Bearer {token}',
        '-H', 'Content-Type: application/json',
        '-d', payload], capture_output=True, text=True)
    print(f'Reminded: {label} in {delta} days')

print(f'Done. Today (TW): {today}')
PYEOF

echo "$(date): date check done"
