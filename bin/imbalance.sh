#!/usr/bin/env bash

source /etc/nzt48/.env

# --- INCOMING ARGUMENTS ---
SYMBOL="$1"
PATTERN="$2"
C2_TIME="$3"
LOW="$4"
HIGH="$5"
FIB="$6"

# --- TELEGRAM BROADCAST FUNCTION ---
send_alert() {
    local MSG="$1"
    while read -r ID; do
        [ -z "$ID" ] && continue
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${ID}" \
            -d text="${MSG}" > /dev/null
    done < /etc/nzt48/subscribers.txt
    echo " -> $MSG"
}

echo "[IMBALANCE SCRIPT] Tracking ${SYMBOL} ${PATTERN} inside ${C2_TIME}"

# --- M15 EXTRACTION (The "Pull 17" Method) ---
API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=M15&num_bars=17"
M15_RESP=$(curl -s "$API_URL")

if [ -z "$M15_RESP" ] || [ "$M15_RESP" == "null" ]; then
    send_alert "⚠️ ${SYMBOL}: H4 Engulfing found, but failed to pull M15 data."
    exit 1
fi

# We take the array, chop off the baby candle at the end, and verify we have 16 left
M15_SUMMARY=$(echo "$M15_RESP" | jq -r '
  if type == "array" and length >= 17 then
    # Slice from index 0 up to (but not including) index 16. This gives us exactly 16 candles.
    .[0:16] as $valid_candles |
    ($valid_candles | length) as $len |
    $valid_candles[0].time as $first_time |
    $valid_candles[-1].time as $last_time |
    "Count: \($len) | First: \($first_time) | Last: \($last_time)"
  else
    "Error: Array length is \(length)"
  end
')

# --- TEMPORARY TELEGRAM ALERT ---
if [ "$PATTERN" == "BULLISH" ]; then ICON="🟢"; else ICON="🔴"; fi

MESSAGE="${ICON} ${SYMBOL} ${PATTERN} ENGULFING
Area of Interest (0.5 Fib): ${FIB}

[FVG HUNTER DIAGNOSTICS]
H4 Candle Open Time: ${C2_TIME}
M15 Data Extracted: ${M15_SUMMARY}

(FVG Logic Pending in next version)"

send_alert "$MESSAGE"