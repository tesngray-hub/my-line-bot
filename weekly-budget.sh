#!/bin/bash
# weekly-budget.sh - 每週五報告本月預算 (jsonl-based, 5/23 改)
# cron: 0 12 * * 5 (UTC 12:00 週五 = 台灣 20:00 週五)

python3 << 'PYEOF'
import json, subprocess, os, re, datetime

env_path = '/root/.claude/channels/line/.env'
token = ''
with open(env_path) as f:
    for line in f:
        line = line.strip()
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line)
        if m: token = m.group(1).strip().strip("'\"")

group_id = 'C00187729030429695b93114aed6d5bab'

budget_path = '/root/my-line-bot/budget.json'
with open(budget_path) as f:
    budget = json.load(f)['monthly']

# 5/23: jsonl vocabulary 跟 budget 不同，加 alias map
CATEGORY_ALIAS = {'飲食': '餐費', '食材': '餐費', '學習': '其他', '住宿': '其他'}
def norm_cat(c):
    return CATEGORY_ALIAS.get(c, c) if c else '其他'

today = datetime.date.today()
month_start = today.replace(day=1).isoformat()

jsonl_path = '/root/.kgi-state/family-expenses.jsonl'
results = []
if os.path.exists(jsonl_path):
    with open(jsonl_path, encoding='utf-8') as f:
        for line in f:
            try:
                row = json.loads(line)
                if (row.get('date') or '') >= month_start:
                    results.append(row)
            except Exception:
                continue

spent = {}
for row in results:
    amount = row.get('amount') or 0
    category = norm_cat(row.get('category'))
    spent[category] = spent.get(category, 0) + amount

total_spent = sum(spent.values())
total_budget = sum(budget.values())

month_str = f"{today.month}月"
week_of_month = (today.day - 1) // 7 + 1
lines = [f"📊 {month_str}預算進度（第{week_of_month}週）\n"]

warnings = []
for cat, limit in budget.items():
    used = spent.get(cat, 0)
    pct = used / limit * 100 if limit else 0
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
