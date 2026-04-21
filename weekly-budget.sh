#!/bin/bash
# weekly-budget.sh - 每週五報告本月預算使用狀況
# cron: 0 12 * * 5 (UTC 12:00 週五 = 台灣 20:00 週五)

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

group_id = 'C00187729030429695b93114aed6d5bab'

# 讀預算設定
budget_path = '/root/my-line-bot/budget.json'
with open(budget_path) as f:
    budget = json.load(f)['monthly']

# 本月範圍
today = datetime.date.today()
month_start = today.replace(day=1).isoformat()

# 查本月 Notion 記帳
payload = json.dumps({
    "filter": {
        "property": "日期",
        "date": {"on_or_after": month_start}
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

# 統計各類別
spent = {}
for page in results:
    props = page['properties']
    amount = props.get('金額', {}).get('number') or 0
    category = (props.get('類別', {}).get('select') or {}).get('name', '其他')
    spent[category] = spent.get(category, 0) + amount

total_spent = sum(spent.values())
total_budget = sum(budget.values())

# 組訊息
month_str = f"{today.month}月"
week_of_month = (today.day - 1) // 7 + 1
lines = [f"📊 {month_str}預算進度（第{week_of_month}週）\n"]

warnings = []
for cat, limit in budget.items():
    used = spent.get(cat, 0)
    pct = used / limit * 100 if limit else 0
    bar = '█' * int(pct // 10) + '░' * (10 - int(pct // 10))
    status = ''
    if pct >= 100:
        status = ' ⚠️ 超支!'
        warnings.append(f'{cat}已超支')
    elif pct >= 80:
        status = ' ⚠️ 接近上限'
        warnings.append(f'{cat}快超支')
    lines.append(f"{cat}：${used:,.0f} / ${limit:,.0f}（{pct:.0f}%）{status}")

lines.append(f"\n💰 總計：${total_spent:,.0f} / ${total_budget:,.0f}（{total_spent/total_budget*100:.0f}%）")
lines.append(f"📝 共 {len(results)} 筆記錄")

if warnings:
    lines.append('\n⚠️ 注意：' + '、'.join(warnings))

msg = '\n'.join(lines)

payload = json.dumps({
    'to': group_id,
    'messages': [{'type': 'text', 'text': msg}]
}, ensure_ascii=False)

subprocess.run(['curl', '-s', '-X', 'POST',
    'https://api.line.me/v2/bot/message/push',
    '-H', f'Authorization: Bearer {token}',
    '-H', 'Content-Type: application/json',
    '-d', payload], capture_output=True)
print(f'Budget report sent. Total: {total_spent}/{total_budget}')
PYEOF

echo "$(date): weekly-budget done"
