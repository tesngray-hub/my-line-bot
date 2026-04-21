#!/bin/bash
# weather-alert.sh - 每天晚上檢查明日天氣，有狀況才推提醒
# cron: 0 11 * * * (UTC 11:00 = 台灣 19:00)

python3 << 'PYEOF'
import json, subprocess, os, re

env_path = '/root/.claude/channels/line/.env'
token = ''
with open(env_path) as f:
    for line in f:
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line.strip())
        if m:
            token = m.group(1).strip().strip("'\"")
            break

group_id = 'C00187729030429695b93114aed6d5bab'

r = subprocess.run(['curl', '-s', '--max-time', '10',
    'wttr.in/桃園?format=j1'],
    capture_output=True, text=True)

try:
    data = json.loads(r.stdout)
    tomorrow = data['weather'][1]
except Exception as e:
    print(f'Failed to parse weather: {e}')
    exit(0)

max_temp = int(tomorrow['maxtempC'])
min_temp = int(tomorrow['mintempC'])
hourly = tomorrow['hourly']

# 下雨天氣碼
RAIN_CODES = {293,296,299,302,305,308,311,314,317,320,323,326,329,332,
              335,338,353,356,359,362,365,368,371,374,377}

has_rain = any(int(h['weatherCode']) in RAIN_CODES for h in hourly)
max_rain_chance = max(int(h.get('chanceofrain', 0)) for h in hourly)
afternoon_rain = any(
    int(h['time']) >= 1200 and int(h['weatherCode']) in RAIN_CODES
    for h in hourly
)

msgs = []

if has_rain and max_rain_chance >= 40:
    if afternoon_rain:
        msgs.append(f'🌧️ 明天午後有雨（降雨機率 {max_rain_chance}%），出門記得帶傘喔！')
    else:
        msgs.append(f'☔ 明天有雨（降雨機率 {max_rain_chance}%），爸爸媽媽記得帶傘！')

if min_temp < 15:
    msgs.append(f'🧥 明天最低 {min_temp}°C，天氣涼，幫兒子多穿一件喔～')
elif min_temp < 20:
    msgs.append(f'🌬️ 明天早晚涼（最低 {min_temp}°C），出門加件外套！')

if max_temp > 33:
    msgs.append(f'☀️ 明天最高 {max_temp}°C，很熱！記得多喝水、防曬！')

if not msgs:
    print(f'No alert. Rain:{has_rain}({max_rain_chance}%) Temp:{min_temp}~{max_temp}°C')
    exit(0)

msg = '🌤️ 小跳跳明日天氣提醒\n' + '\n'.join(msgs) + f'\n（明天 {min_temp}~{max_temp}°C）'

payload = json.dumps({
    'to': group_id,
    'messages': [{'type': 'text', 'text': msg}]
}, ensure_ascii=False)

subprocess.run(['curl', '-s', '-X', 'POST',
    'https://api.line.me/v2/bot/message/push',
    '-H', f'Authorization: Bearer {token}',
    '-H', 'Content-Type: application/json',
    '-d', payload], capture_output=True)
print(f'Alert sent: {msg[:80]}')
PYEOF

echo "$(date): weather-alert done"
