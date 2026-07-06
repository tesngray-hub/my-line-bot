#!/bin/bash
# expense-check.sh - 檢查超過 3 天沒記帳就提醒 (jsonl-based, 5/23 改)
# cron: 0 12 * * * (UTC 12:00 = 台灣 20:00，每天跑)

python3 << 'PYEOF'
import json, subprocess, re, datetime, os

env_path = '/root/.claude/channels/line/.env'
token = ''
with open(env_path) as f:
    for line in f:
        line = line.strip()
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line)
        if m: token = m.group(1).strip().strip("'\"")

group_id = 'C00187729030429695b93114aed6d5bab'

jsonl_path = '/root/.kgi-state/family-expenses.jsonl'
if not os.path.exists(jsonl_path):
    print('No jsonl file')
    raise SystemExit(0)

last_date_str = ''
with open(jsonl_path, encoding='utf-8') as f:
    for line in f:
        try:
            row = json.loads(line)
            d = row.get('date', '')
            if d and d > last_date_str:
                last_date_str = d
        except Exception:
            continue

if not last_date_str:
    print('No expense records found')
    raise SystemExit(0)

last_date = datetime.date.fromisoformat(last_date_str[:10])
today = datetime.date.today()
days_since = (today - last_date).days

print(f'Last expense: {last_date_str}, {days_since} days ago')

if days_since >= 3:
    msg = f'💸 爸爸媽媽，小跳跳發現已經 {days_since} 天沒有記帳了！\n最後一筆是 {last_date.month}/{last_date.day}。\n最近有消費的話，記得跟小跳跳說喔 📝'
    payload = json.dumps({
        'to': group_id,
        'messages': [{'type': 'text', 'text': msg}]
    }, ensure_ascii=False)
    subprocess.run(['curl', '-s', '-X', 'POST',
        'https://api.line.me/v2/bot/message/push',
        '-H', f'Authorization: Bearer {token}',
        '-H', 'Content-Type: application/json',
        '-d', payload], capture_output=True)
    print(f'Reminder sent: {days_since} days since last expense')
PYEOF

echo "$(date): expense-check done"
