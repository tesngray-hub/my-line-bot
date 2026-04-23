import json, subprocess, os, re, datetime, sys

env_path = os.path.expanduser('~/.claude/channels/line/.env')
notion_token = ''
line_token = ''
with open(env_path) as ef:
    for line in ef:
        m = re.match(r'^NOTION_TOKEN=(.*)', line.strip())
        if m: notion_token = m.group(1).strip().strip("'\"")
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line.strip())
        if m: line_token = m.group(1).strip().strip("'\"")

today_raw = sys.argv[1] if len(sys.argv) > 1 else datetime.date.today().isoformat()
group_id  = sys.argv[2] if len(sys.argv) > 2 else 'C00187729030429695b93114aed6d5bab'

_d = datetime.date.fromisoformat(today_raw)
today_label = str(_d.month) + '/' + str(_d.day)

query = json.dumps({
    'filter': {'property': '日期', 'date': {'equals': today_raw}},
    'page_size': 50
})
r = subprocess.run(['curl', '-s', '-X', 'POST',
    'https://api.notion.com/v1/databases/ac9c0e6320314a57ba4243f3aca29d3b/query',
    '-H', 'Authorization: Bearer ' + notion_token,
    '-H', 'Content-Type: application/json',
    '-H', 'Notion-Version: 2022-06-28',
    '-d', query], capture_output=True, text=True)

data = json.loads(r.stdout)
results = data.get('results', [])

if not results:
    print('今天沒有記帳紀錄，不發送')
    sys.exit(0)

by_person = {}
person_total = {}
for page in results:
    props = page.get('properties', {})
    amount = props.get('金額', {}).get('number', 0) or 0
    category = (props.get('類別', {}).get('select') or {}).get('name', '其他')
    payer = (props.get('誰付', {}).get('select') or {}).get('name', '其他')
    if payer not in by_person:
        by_person[payer] = {}
        person_total[payer] = 0
    by_person[payer][category] = by_person[payer].get(category, 0) + amount
    person_total[payer] += amount

grand_total = sum(person_total.values())
ICONS = {'爸爸': '\U0001f468', '媽媽': '\U0001f469', '共同': '\U0001f46a', '其他': '\U0001f464'}
order = ['爸爸', '媽媽', '共同'] + [p for p in by_person if p not in ('爸爸', '媽媽', '共同')]

lines = ['\U0001f4ca ' + today_label + ' 記帳總結', '']
for person in order:
    if person not in by_person:
        continue
    icon = ICONS.get(person, '\U0001f464')
    amt = person_total[person]
    lines.append(icon + ' ' + person + '：$' + '{:,.0f}'.format(amt))
    for cat, a in sorted(by_person[person].items(), key=lambda x: -x[1]):
        lines.append('   ' + cat + ' $' + '{:,.0f}'.format(a))
    lines.append('')
lines.append('\U0001f4b0 合計：$' + '{:,.0f}'.format(grand_total) + '（共 ' + str(len(results)) + ' 筆）')
msg = '\n'.join(lines)

payload = json.dumps({'to': group_id, 'messages': [{'type': 'text', 'text': msg}]}, ensure_ascii=False)
subprocess.run(['curl', '-s', '-X', 'POST', 'https://api.line.me/v2/bot/message/push',
    '-H', 'Authorization: Bearer ' + line_token,
    '-H', 'Content-Type: application/json',
    '-d', payload], capture_output=True)
print('Sent: ' + today_label + ' total=' + str(grand_total))
