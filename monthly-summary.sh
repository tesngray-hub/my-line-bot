#!/bin/bash
# monthly-summary.sh - 每月1日推上個月帳單總結 (jsonl-based, 5/23 改)
# cron: 0 1 1 * * (每月1日 UTC 01:00 = 台灣 09:00)

python3 << 'PYEOF'
import json, subprocess, os, re, datetime

env_path = '/root/.claude/channels/line/.env'
token = ''
with open(env_path) as f:
    for line in f:
        line = line.strip()
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line)
        if m: token = m.group(1).strip().strip("'\"")

CATEGORY_ALIAS = {'飲食': '餐費', '食材': '餐費', '學習': '其他', '住宿': '其他'}
def norm_cat(c):
    return CATEGORY_ALIAS.get(c, c) if c else '其他'

today = datetime.date.today()
first_this_month = today.replace(day=1)
last_month_end = first_this_month - datetime.timedelta(days=1)
last_month_start = last_month_end.replace(day=1)
lm_start_str = last_month_start.isoformat()
lm_end_str = last_month_end.isoformat()

jsonl_path = '/root/.kgi-state/family-expenses.jsonl'
results = []
if os.path.exists(jsonl_path):
    with open(jsonl_path, encoding='utf-8') as f:
        for line in f:
            try:
                row = json.loads(line)
                d = row.get('date') or ''
                if lm_start_str <= d <= lm_end_str:
                    results.append(row)
            except Exception:
                continue

if not results:
    print("No expense data for last month")
    raise SystemExit(0)

total = 0
by_category = {}
by_person = {}
for row in results:
    amount = row.get('amount') or 0
    category = norm_cat(row.get('category'))
    person = row.get('person') or '未知'
    total += amount
    by_category[category] = by_category.get(category, 0) + amount
    by_person[person] = by_person.get(person, 0) + amount

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
