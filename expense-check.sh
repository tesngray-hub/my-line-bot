#!/bin/bash
# expense-check.sh - 檢查超過 3 天沒記帳就提醒
# cron: 0 12 * * * (UTC 12:00 = 台灣 20:00，每天跑)

python3 << 'PYEOF'
import json, subprocess, re, datetime

env_path = '/root/.claude/channels/line/.env'
token = ''
notion_token = ''
with open(env_path) as f:
    for line in f:
        line = line.strip()
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line)
        if m: token = m.group(1).strip().strip("'\"")
        m = re.match(r'^NOTION_TOKEN=(.*)', line)
        if m: notion_token = m.group(1).strip().strip("'\"")

group_id = 'C00187729030429695b93114aed6d5bab'

# 查最近一筆記帳
r = subprocess.run(['curl', '-s', '-X', 'POST',
    'https://api.notion.com/v1/databases/ac9c0e6320314a57ba4243f3aca29d3b/query',
    '-H', f'Authorization: Bearer {notion_token}',
    '-H', 'Content-Type: application/json',
    '-H', 'Notion-Version: 2022-06-28',
    '-d', '{"sorts":[{"property":"日期","direction":"descending"}],"page_size":1}'],
    capture_output=True, text=True)

data = json.loads(r.stdout)
results = data.get('results', [])

if not results:
    print('No expense records found')
    exit(0)

last_date_str = results[0]['properties'].get('日期', {}).get('date', {}).get('start', '')
if not last_date_str:
    exit(0)

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
