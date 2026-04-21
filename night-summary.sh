#!/bin/bash
# 每天晚上 10:30（台灣時間）發今日記帳總結，按爸爸/媽媽分組
# Taiwan 10:30pm = UTC 14:30
# cron: 30 14 * * * /root/my-line-bot/night-summary.sh >> /tmp/night-summary.log 2>&1

GROUP_ID="C00187729030429695b93114aed6d5bab"
DATE_TW=$(TZ=Asia/Taipei date "+%Y-%m-%d")

python3 << PYEOF
import json, subprocess, os, re, datetime

env_path = os.path.expanduser("~/.claude/channels/line/.env")
notion_token = ""
line_token = ""
with open(env_path) as f:
    for line in f:
        m = re.match(r"^NOTION_TOKEN=(.*)", line.strip())
        if m: notion_token = m.group(1).strip().strip("\"'")
        m = re.match(r"^LINE_CHANNEL_ACCESS_TOKEN=(.*)", line.strip())
        if m: line_token = m.group(1).strip().strip("\"'")

today_raw = "$DATE_TW"
_d = datetime.date.fromisoformat(today_raw)
today_label = f"{_d.month}/{_d.day}"

query = json.dumps({"filter": {"property": "日期", "date": {"equals": today_raw}}, "page_size": 50})
r = subprocess.run(["curl","-s","-X","POST","https://api.notion.com/v1/databases/ac9c0e6320314a57ba4243f3aca29d3b/query","-H",f"Authorization: Bearer {notion_token}","-H","Content-Type: application/json","-H","Notion-Version: 2022-06-28","-d",query], capture_output=True, text=True)

data = json.loads(r.stdout)
results = data.get("results", [])
if not results:
    print("今天沒有記帳紀錄，不發送")
    exit(0)

by_person = {}
person_total = {}
for page in results:
    props = page.get("properties", {})
    amount = props.get("金額", {}).get("number", 0) or 0
    category = (props.get("類別", {}).get("select") or {}).get("name", "其他")
    payer = (props.get("誰付", {}).get("select") or {}).get("name", "其他")
    if payer not in by_person:
        by_person[payer] = {}
        person_total[payer] = 0
    by_person[payer][category] = by_person[payer].get(category, 0) + amount
    person_total[payer] += amount

grand_total = sum(person_total.values())
ICONS = {"爸爸": "👨", "媽媽": "👩", "共同": "👨\u200d👩", "其他": "👤"}
lines = [f"📊 {today_label} 記帳總結\n"]
order = ["爸爸", "媽媽", "共同"] + [p for p in by_person if p not in ("爸爸","媽媽","共同")]
for person in order:
    if person not in by_person: continue
    icon = ICONS.get(person, "👤")
    lines.append(f"{icon} {person}：${person_total[person]:,.0f}")
    for cat, amt in sorted(by_person[person].items(), key=lambda x: -x[1]):
        lines.append(f"   {cat} ${amt:,.0f}")
    lines.append("")
lines.append(f"💰 合計：${grand_total:,.0f}（共 {len(results)} 筆）")
msg = "\n".join(lines)

payload = json.dumps({"to": "C00187729030429695b93114aed6d5bab", "messages": [{"type": "text", "text": msg}]}, ensure_ascii=False)
subprocess.run(["curl","-s","-X","POST","https://api.line.me/v2/bot/message/push","-H",f"Authorization: Bearer {line_token}","-H","Content-Type: application/json","-d",payload], capture_output=True)
print(f"Sent: {today_label} total={grand_total}")
PYEOF

echo "$(date): night summary done"

