#!/bin/bash
# 每天晚上 10:30（台灣時間）發今日記帳總結，按爸爸/媽媽分組
# cron: 30 14 * * * /root/my-line-bot/night-summary.sh >> /tmp/night-summary.log 2>&1
DATE_TW=$(TZ=Asia/Taipei date '+%Y-%m-%d')
python3 /root/my-line-bot/night-summary.py "$DATE_TW" "C00187729030429695b93114aed6d5bab"
echo "$(date): night summary done"
