#!/bin/bash
# weekly-preview.sh - 週日晚上推下週行程預告
# cron: 0 12 * * 0 (週日 UTC 12:00 = 台灣 20:00)

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

# 下週範圍（台灣時間，VPS 是 UTC，加 8 小時）
today_utc = datetime.date.today()
today_tw = today_utc + datetime.timedelta(hours=8)  # 近似
days_until_monday = (7 - today_tw.weekday()) % 7 or 7
next_monday = today_tw + datetime.timedelta(days=days_until_monday)
next_sunday = next_monday + datetime.timedelta(days=6)

week_events = [
    e for e in data['events']
    if next_monday.isoformat() <= e['date'] <= next_sunday.isoformat()
]

WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日']
month_str = f"{next_monday.month}/{next_monday.day}"
end_str = f"{next_sunday.month}/{next_sunday.day}"

if not week_events:
    msg = f"📅 下週（{month_str}～{end_str}）目前沒有行程\n放輕鬆的一週！😊"
else:
    lines = [f"📅 下週行程預告（{month_str}～{end_str}）\n"]
    by_date = {}
    for e in week_events:
        by_date.setdefault(e['date'], []).append(e)

    for date_str in sorted(by_date.keys()):
        d = datetime.date.fromisoformat(date_str)
        weekday = WEEKDAYS[d.weekday()]
        lines.append(f"【{d.month}/{d.day}（{weekday}）】")
        for e in by_date[date_str]:
            lines.append(f"  • {e['title']}（{e.get('by','小跳跳')}）")
        lines.append("")

    lines.append("下週也要加油喔！💪")
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
