#!/bin/bash
# weather-alert.sh
# 早上 6:20 報今日天氣：cron 20 22 * * * ... morning
# 晚上 10:00 報明日提醒：cron  0 14 * * * ... night

MODE="${1:-morning}"  # morning 或 night

python3 << PYEOF
import json, subprocess, re, sys

mode = '${MODE}'

env_path = '/root/.claude/channels/line/.env'
token = ''
with open(env_path) as f:
    for line in f:
        m = re.match(r'^LINE_CHANNEL_ACCESS_TOKEN=(.*)', line.strip())
        if m:
            token = m.group(1).strip().strip('"\'')
            break

group_id = 'C00187729030429695b93114aed6d5bab'

RAIN_CODES = {293,296,299,302,305,308,311,314,317,320,323,326,329,332,
              335,338,353,356,359,362,365,368,371,374,377}

def fetch_weather(location):
    r = subprocess.run(['curl', '-s', '--max-time', '10',
        f'wttr.in/{location}?format=j1'],
        capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return None

def parse_day(day_data):
    max_temp = int(day_data['maxtempC'])
    min_temp = int(day_data['mintempC'])
    hourly   = day_data['hourly']
    desc = (day_data['hourly'][4].get('lang_zh') or [{}])[0].get('value', '') or \
           (day_data['hourly'][4].get('weatherDesc') or [{}])[0].get('value', '')
    max_rain = max(int(h.get('chanceofrain', 0)) for h in hourly)
    has_rain = any(int(h['weatherCode']) in RAIN_CODES for h in hourly)
    afternoon_rain = any(int(h['time']) >= 1200 and int(h['weatherCode']) in RAIN_CODES for h in hourly)
    return max_temp, min_temp, desc, max_rain, has_rain, afternoon_rain

# ── 早上模式：報今日兩地天氣 ──────────────────────────
if mode == 'morning':
    def format_today(location_query, label):
        data = fetch_weather(location_query)
        if not data:
            return f'{label}：資料取得失敗'
        max_t, min_t, desc, max_rain, has_rain, afternoon_rain = parse_day(data['weather'][0])

        icon = '🌧️' if (has_rain and max_rain >= 60) else \
               '🌦️' if (has_rain and max_rain >= 30) else \
               '☀️' if max_t > 32 else '🧥' if min_t < 15 else '⛅'

        lines = [f'{icon} {label}：{min_t}~{max_t}°C']
        if desc:
            lines.append(f'   {desc}')
        if has_rain and max_rain >= 30:
            tag = '午後有雨' if afternoon_rain else '有雨'
            lines.append(f'   ☔ {tag}，降雨機率 {max_rain}%')
        if min_t < 15:
            lines.append(f'   🧥 天氣涼，記得加外套！')
        if max_t > 33:
            lines.append(f'   🥵 很熱，多喝水防曬！')
        return '\n'.join(lines)

    guishan = format_today('龜山區,桃園', '桃園龜山')
    taipei  = format_today('台北', '台北市區')
    msg = f'🌤️ 早安！今日天氣\n\n{guishan}\n\n{taipei}'

# ── 晚上模式：報明日兩地天氣 + 建議 ─────────────────────
else:
    def format_tomorrow_block(location_query, label):
        data = fetch_weather(location_query)
        if not data:
            return None, f'{label}：資料取得失敗'
        max_t, min_t, desc, max_rain, has_rain, afternoon_rain = parse_day(data['weather'][1])

        icon = '🌧️' if (has_rain and max_rain >= 60) else \
               '🌦️' if (has_rain and max_rain >= 30) else \
               '☀️' if max_t > 32 else '🧥' if min_t < 15 else '⛅'

        lines = [f'{icon} {label}：{min_t}~{max_t}°C']
        if has_rain and max_rain >= 30:
            tag = '午後有雨' if afternoon_rain else '有雨'
            lines.append(f'   ☔ {tag}，降雨機率 {max_rain}%')

        info = {'max_t': max_t, 'min_t': min_t, 'has_rain': has_rain,
                'max_rain': max_rain, 'afternoon_rain': afternoon_rain}
        return info, '\n'.join(lines)

    g_info, g_block = format_tomorrow_block('龜山區,桃園', '桃園龜山')
    t_info, t_block = format_tomorrow_block('台北', '台北市區')

    # 綜合建議
    tips = []
    if g_info and t_info:
        min_t_both = min(g_info['min_t'], t_info['min_t'])
        max_t_both = max(g_info['max_t'], t_info['max_t'])
        either_rain = (g_info['has_rain'] and g_info['max_rain'] >= 30) or \
                      (t_info['has_rain'] and t_info['max_rain'] >= 30)

        if either_rain:
            tips.append('☔ 明天有雨，出門記得帶傘！')
        if min_t_both < 15:
            tips.append(f'🧥 最低 {min_t_both}°C，幫兒子多穿一件、記得加外套！')
        elif min_t_both < 20:
            tips.append(f'🌬️ 早晚涼（{min_t_both}°C），帶件薄外套！')
        if max_t_both > 33:
            tips.append(f'🥵 最高 {max_t_both}°C，防曬多喝水！')
        if not tips:
            tips.append('😊 明天天氣不錯，出門不需要特別準備！')

    tip_str = '\n'.join(tips)
    msg = f'🌙 明日天氣提醒\n\n{g_block}\n\n{t_block}\n\n{tip_str}'

# ── 送出 ──────────────────────────────────────────────
payload = json.dumps({
    'to': group_id,
    'messages': [{'type': 'text', 'text': msg}]
}, ensure_ascii=False)

subprocess.run(['curl', '-s', '-X', 'POST',
    'https://api.line.me/v2/bot/message/push',
    '-H', f'Authorization: Bearer {token}',
    '-H', 'Content-Type: application/json',
    '-d', payload], capture_output=True)
print(f'[{mode}] Sent: {msg[:60]}')
PYEOF

echo "$(date): weather-alert [${MODE}] done"
