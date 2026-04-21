#!/bin/bash
# Usage: add-event.sh "2026-05-01" "看牙醫" "爸爸"
DATE="$1"
TITLE="$2"
BY="${3:-小跳跳}"

python3 -c "
import json, sys
path = '/root/my-line-bot/events.json'
with open(path) as f:
    data = json.load(f)
data['events'].append({'date': sys.argv[1], 'title': sys.argv[2], 'by': sys.argv[3]})
with open(path, 'w') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('OK')
" "$DATE" "$TITLE" "$BY"

cd /root/my-line-bot
git add events.json
git commit -m "Add event: $TITLE on $DATE"
git push
