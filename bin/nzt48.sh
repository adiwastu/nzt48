#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("USDJPY" "XAUUSD")
TIMEFRAME="H4" 

CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")
echo "[${CURRENT_TIME}] V0.2 Stable: Scanning H4 Displacement..."

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

for SYMBOL in "${SYMBOLS[@]}"; do
    # Pulling 2 bars is enough now since we only care about the last two
    API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=${TIMEFRAME}&num_bars=2"
    RESP=$(curl -s "$API_URL")

    if [ -z "$RESP" ] || [ "$RESP" == "null" ]; then
        continue
    fi

    RESULT=$(echo "$RESP" | jq -r '
      if type == "array" and length >= 2 then
        .[0] as $c1 |
        .[1] as $c2 |
        
        # BULLISH: Red then Green + Close 2 > High 1
        if ($c1.close < $c1.open) and ($c2.close > $c2.open) and ($c2.close > $c1.high) then
          "BULLISH \($c2.low) \($c2.high)"
        
        # BEARISH: Green then Red + Close 2 < Low 1
        elif ($c1.close > $c1.open) and ($c2.close < $c2.open) and ($c2.close < $c1.low) then
          "BEARISH \($c2.low) \($c2.high)"
        
        else
          "NONE 0 0"
        end
      else
        "NONE 0 0"
      end
    ')

    read PATTERN LOW HIGH <<< "$RESULT"

    if [ "$PATTERN" == "BULLISH" ]; then
        FIB=$(awk "BEGIN {print ($HIGH + $LOW) / 2}")
        send_alert "🟢 ${SYMBOL}: ada engulfing bullish, low di ${LOW}, high di ${HIGH}, 0.5 fib di ${FIB}."
    elif [ "$PATTERN" == "BEARISH" ]; then
        FIB=$(awk "BEGIN {print ($HIGH + $LOW) / 2}")
        send_alert "🔴 ${SYMBOL}: ada engulfing bearish, low di ${LOW}, high di ${HIGH}, 0.5 fib di ${FIB}."
    else
        send_alert "⚪ ${SYMBOL}: ga ada engulfing H4."
    fi
    sleep 1
done