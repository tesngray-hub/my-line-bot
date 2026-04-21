#!/bin/bash
# event-reminder.sh - 每天晚上推明天的行程提醒到家庭群組（按人分開列）

python3 << 'PYEOF'
import json, datetime, subprocess, os, re

env_path = '/root/.claude/channels/line/.env'
token = ''
with open(env_path) as f:
    for line in f:
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line.strip())
        if m:
            token = m.group(1).strip().strip("'\"")
            break

events_path = '/root/my-line-bot/events.json'
with open(events_path) as f:
    data = json.load(f)

tomorrow = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
tomorrow_events = [e for e in data['events'] if e['date'] == tomorrow]

if not tomorrow_events:
    print("No events tomorrow, skipping")
    exit(0)

d = datetime.date.fromisoformat(tomorrow)
date_str = f"{d.month}/{d.day}"

# 按人分組
groups = {'爸爸': [], '媽媽': [], '全家': [], '其他': []}
for e in tomorrow_events:
    by = e.get('by', '其他')
    if by in groups:
        groups[by].append(e['title'])
    else:
        groups['其他'].append(e['title'])

lines = [f"📅 明天 {date_str} 行程提醒～"]
if groups['爸爸']:
    lines.append("\n👨 爸爸：")
    for t in groups['爸爸']:
        lines.append(f"• {t}")
if groups['媽媽']:
    lines.append("\n👩 媽媽：")
    for t in groups['媽媽']:
        lines.append(f"• {t}")
if groups['全家']:
    lines.append("\n👨‍👩‍👦 全家：")
    for t in groups['全家']:
        lines.append(f"• {t}")
if groups['其他']:
    lines.append("\n📌 其他：")
    for t in groups['其他']:
        lines.append(f"• {t}")

lines.append("\n記得提早準備喔！🌙")
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
