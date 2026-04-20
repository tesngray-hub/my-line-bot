@echo off
cd /d C:\Users\tesng\my-line-bot
echo y | claude --dangerously-load-development-channels server:line-channel
pause
