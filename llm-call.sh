#!/bin/bash
# llm-call.sh — 直接 call Anthropic API（取代 `claude --print` CLI auth 過期問題）
#
# 用法:
#   PROMPT="你是小跳跳..."
#   RESPONSE=$(echo "$PROMPT" | /root/my-line-bot/llm-call.sh)
#   或: RESPONSE=$(/root/my-line-bot/llm-call.sh <<< "$PROMPT")
#
# 失敗 (網路/401/etc) → return empty string + non-zero exit code，
# caller 應 detect empty 用 fallback。
#
# 不再有「錯誤訊息洩漏到 LINE 訊息」的 bug。

set -e

ENV_FILE="${ANTHROPIC_ENV_FILE:-/root/.claude/channels/line/.env}"
MODEL="${LLM_MODEL:-claude-haiku-4-5-20251001}"
MAX_TOKENS="${LLM_MAX_TOKENS:-500}"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "[llm-call] no ANTHROPIC_API_KEY in $ENV_FILE" >&2
  exit 2
fi

# Read prompt from stdin
PROMPT=$(cat)
if [ -z "$PROMPT" ]; then
  echo "[llm-call] empty prompt on stdin" >&2
  exit 3
fi

PAYLOAD=$(python3 -c '
import json, sys
prompt = sys.stdin.read()
print(json.dumps({
    "model": sys.argv[1],
    "max_tokens": int(sys.argv[2]),
    "messages": [{"role": "user", "content": prompt}]
}))
' "$MODEL" "$MAX_TOKENS" <<< "$PROMPT")

RESP=$(curl -sS --max-time 60 \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD" \
  https://api.anthropic.com/v1/messages 2>&1) || {
    echo "[llm-call] curl failed: $RESP" >&2
    exit 4
  }

# Parse response — return only text content. If error or no content → empty + nonzero.
echo "$RESP" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if d.get("type") == "error" or "error" in d:
        err = d.get("error")
        print("[llm-call] api error: " + str(err), file=sys.stderr)
        sys.exit(5)
    text = "".join(b.get("text","") for b in d.get("content",[]) if b.get("type")=="text").strip()
    if not text:
        print("[llm-call] empty content", file=sys.stderr)
        sys.exit(6)
    print(text)
except json.JSONDecodeError as e:
    print("[llm-call] json parse fail: " + str(e), file=sys.stderr)
    sys.exit(7)
'
