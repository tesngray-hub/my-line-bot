#!/bin/bash
# 每天晚上 10:30（台灣時間）發今日記帳總結
# Taiwan 10:30pm = UTC 14:30
# cron: 30 14 * * * /root/my-line-bot/night-summary.sh >> /tmp/night-summary.log 2>&1

source ~/.claude/channels/line/.env
GROUP_ID="C00187729030429695b93114aed6d5bab"
DATE_TW=$(TZ=Asia/Taipei date '+%Y-%m-%d')

python3 << PYEOF
import json, subprocess, os, re, datetime

env_path = os.path.expanduser('~/.claude/channels/line/.env')
notion_token = ''
line_token = ''
with open(env_path) as f:
    for line in f:
        m = re.match(r'^NOTION_TOKEN=(.*)', line.strip())
        if m: notion_token = m.group(1).strip().strip("'\"")
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line.strip())
        if m: line_token = m.group(1).strip().strip("'\"")

# 查今天的帳
today = '$DATE_TW'
query = json.dumps({
    "filter": {
        "property": "日期",
        "date": {"equals": today}
    },
    "page_size": 50
})

r = subprocess.run([
    'curl', '-s', '-X', 'POST',
    'https://api.notion.com/v1/databases/ac9c0e6320314a57ba4243f3aca29d3b/query',
    '-H', f'Authorization: Bearer {notion_token}',
    '-H', 'Content-Type: application/json',
    '-H', 'Notion-Version: 2022-06-28',
    '-d', query
], capture_output=True, text=True)

data = json.loads(r.stdout)
results = data.get('results', [])

if not results:
    print('今天沒有記帳紀錄，不發送')
    exit(0)

# 整理資料
total = 0
categories = {}
items = []
for page in results:
    props = page.get('properties', {})
    amount = props.get('金額', {}).get('number', 0) or 0
    category = props.get('類別', {}).get('select', {})
    category = category.get('name', '其他') if category else '其他'
    desc_arr = props.get('說明', {}).get('rich_text', [])
    desc = desc_arr[0]['text']['content'] if desc_arr else ''
    payer = props.get('誰付', {}).get('select', {})
    payer = payer.get('name', '') if payer else ''

    total += amount
    categories[category] = categories.get(category, 0) + amount
    if desc:
        items.append(f'{desc} ${amount}')

# 組訊息
cat_lines = '\n'.join([f'  {k}：${v}' for k, v in sorted(categories.items(), key=lambda x: -x[1])])
items_line = '、'.join(items[:5]) + ('...' if len(items) > 5 else '')

msg = f'今天的帳 📊\n\n合計：${total}\n{cat_lines}'
if items_line:
    msg += f'\n\n明細：{items_line}'

# 送出
payload = json.dumps({'to': '$GROUP_ID', 'messages': [{'type': 'text', 'text': msg}]}, ensure_ascii=False)
subprocess.run([
    'curl', '-s', '-X', 'POST',
    'https://api.line.me/v2/bot/message/push',
    '-H', f'Authorization: Bearer {line_token}',
    '-H', 'Content-Type: application/json',
    '-d', payload
])
print(f'Sent summary: total={total}, categories={categories}')
PYEOF

echo "$(date): night summary done"
