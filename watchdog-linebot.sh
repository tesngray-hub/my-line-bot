#!/bin/bash
# Watchdog: restart bot if unresponsive
LOG=/tmp/watchdog.log
PANE_SNAPSHOT=/tmp/watchdog_pane.txt
PANE_TIMESTAMP=/tmp/watchdog_pane_ts.txt
STUCK_MINUTES=8

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> $LOG; }

# 1. port 3456 掛掉 → 重啟 service（tmux 死掉 systemd 會自己重啟）
if ! ss -tlnp | grep -q 3456; then
  log "RESTART: port 3456 down"
  sudo systemctl restart linebot
  exit 0
fi

# 2. tmux 不在 → systemd 會重啟，不管
if ! tmux has-session -t linebot 2>/dev/null; then
  log "tmux dead, waiting for systemd"
  exit 0
fi

# 3. 偵測 Claude 卡住：比對 tmux pane 輸出是否有變化
CURRENT_PANE=$(tmux capture-pane -t linebot -p -S -5 2>/dev/null | md5sum)

if [ -f "$PANE_SNAPSHOT" ] && [ -f "$PANE_TIMESTAMP" ]; then
  LAST_PANE=$(cat "$PANE_SNAPSHOT")
  LAST_TS=$(cat "$PANE_TIMESTAMP")
  NOW=$(date +%s)
  STUCK_SECS=$(( STUCK_MINUTES * 60 ))

  if [ "$CURRENT_PANE" = "$LAST_PANE" ]; then
    FROZEN=$(( NOW - LAST_TS ))
    if [ $FROZEN -gt $STUCK_SECS ]; then
      log "RESTART: pane frozen for ${FROZEN}s, restarting tmux session"
      tmux kill-session -t linebot
      # systemd 的監控迴圈會偵測到 session 消失並退出，觸發 systemd 重啟
      exit 0
    else
      log "OK: pane unchanged for ${FROZEN}s (threshold ${STUCK_SECS}s)"
    fi
  else
    # pane 有變化，更新快照與時間戳
    echo "$CURRENT_PANE" > "$PANE_SNAPSHOT"
    echo "$NOW" > "$PANE_TIMESTAMP"
    log "OK: pane active"
  fi
else
  # 第一次執行，建立快照
  echo "$CURRENT_PANE" > "$PANE_SNAPSHOT"
  date +%s > "$PANE_TIMESTAMP"
  log "OK: snapshot initialized"
fi
