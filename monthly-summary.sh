#!/bin/bash
# monthly-summary.sh - 每月1日推上個月帳單總結
# cron: 0 1 1 * * (每月1日 UTC 01:00 = 台灣 09:00)

python3 << 'PYEOF'
import json, subprocess, os, re, datetime

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

# 上個月的範圍
today = datetime.date.today()
first_this_month = today.replace(day=1)
last_month_end = first_this_month - datetime.timedelta(days=1)
last_month_start = last_month_end.replace(day=1)

# 查 Notion 記帳資料庫
payload = json.dumps({
    "filter": {
        "and": [
            {"property": "日期", "date": {"on_or_after": last_month_start.isoformat()}},
            {"property": "日期", "date": {"on_or_before": last_month_end.isoformat()}}
        ]
    },
    "page_size": 100
})

r = subprocess.run(['curl', '-s', '-X', 'POST',
    'https://api.notion.com/v1/databases/ac9c0e6320314a57ba4243f3aca29d3b/query',
    '-H', f'Authorization: Bearer {notion_token}',
    '-H', 'Content-Type: application/json',
    '-H', 'Notion-Version: 2022-06-28',
    '-d', payload], capture_output=True, text=True)

data = json.loads(r.stdout)
results = data.get('results', [])

if not results:
    print("No expense data for last month")
    exit(0)

# 統計
total = 0
by_category = {}
by_person = {}
for page in results:
    props = page['properties']
    amount = props.get('金額', {}).get('number') or 0
    category = (props.get('類別', {}).get('select') or {}).get('name', '其他')
    person = (props.get('誰付', {}).get('select') or {}).get('name', '未知')
    total += amount
    by_category[category] = by_category.get(category, 0) + amount
    by_person[person] = by_person.get(person, 0) + amount

# 組訊息
month_str = f"{last_month_start.month}月"
lines = [f"📊 {month_str}家庭帳單總結\n"]
lines.append(f"💰 總支出：${total:,.0f}\n")

lines.append("📂 類別分佈：")
for cat, amt in sorted(by_category.items(), key=lambda x: -x[1]):
    pct = amt / total * 100 if total else 0
    lines.append(f"  {cat}：${amt:,.0f}（{pct:.0f}%）")

lines.append("\n👤 付款人：")
for person, amt in sorted(by_person.items(), key=lambda x: -x[1]):
    lines.append(f"  {person}：${amt:,.0f}")

lines.append(f"\n共 {len(results)} 筆記錄 ✅")
msg = "\n".join(lines)

payload = json.dumps({
    "to": "C00187729030429695b93114aed6d5bab",
    "messages": [{"type": "text", "text": msg}]
}, ensure_ascii=False)

r = subprocess.run(['curl', '-s', '-X', 'POST',
    'https://api.line.me/v2/bot/message/push',
    '-H', f'Authorization: Bearer {token}',
    '-H', 'Content-Type: application/json',
    '-d', payload], capture_output=True, text=True)
print(r.stdout[:200])
PYEOF
