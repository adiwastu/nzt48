#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("USDJPY" "XAUUSD")
TIMEFRAME="H4" 

# --- ARGUMENT PARSING ---
DEBUG=false
TARGET_TIME=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --debug) DEBUG=true; shift ;;
        --target) TARGET_TIME="$2"; shift 2 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
done

CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")
if [ "$DEBUG" = true ]; then
    echo "[${CURRENT_TIME}] 🛠️ V0.3 DEBUG MODE: Telegram is DISABLED."
else
    echo "[${CURRENT_TIME}] 🚀 V0.3 Live: Scanning H4 Displacement..."
fi

# --- TELEGRAM BROADCAST FUNCTION ---
send_alert() {
    local MSG="$1"
    if [ "$DEBUG" = true ]; then
        # Just print it to the console, do not fire the curl
        echo " 📟 [TEST ALERT] -> $MSG"
        return
    fi

    while read -r ID; do
        [ -z "$ID" ] && continue
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${ID}" \
            -d text="${MSG}" > /dev/null
    done < /etc/nzt48/subscribers.txt
    echo " -> $MSG"
}

for SYMBOL in "${SYMBOLS[@]}"; do
    
    # --- API ROUTING ---
    if [ -n "$TARGET_TIME" ]; then
        # If a target time is provided, calculate the start time (8 hours prior) to get exactly 2 H4 bars
        START_TIME=$(date -d "${TARGET_TIME} - 8 hours ago" +"%Y-%m-%dT%H:%M:%S")
        FORMATTED_TARGET=$(date -d "${TARGET_TIME}" +"%Y-%m-%dT%H:%M:%S")
        
        API_URL="https://api.hotland3x3.my.id/fetch_data_range?symbol=${SYMBOL}&timeframe=${TIMEFRAME}&start=${START_TIME}&end=${FORMATTED_TARGET}"
        
        if [ "$DEBUG" = true ]; then
            echo " ⏳ Fetching historical range: $START_TIME to $FORMATTED_TARGET"
        fi
    else
        # Standard live behavior
        API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=${TIMEFRAME}&num_bars=2"
    fi

    RESP=$(curl -s "$API_URL")

    if [ -z "$RESP" ] || [ "$RESP" == "null" ]; then
        if [ "$DEBUG" = true ]; then echo "⚠️ Null response for $SYMBOL"; fi
        continue
    fi

    # Using .[-2] and .[-1] ensures we always grab the LAST two bars of the array safely
    RESULT=$(echo "$RESP" | jq -r '
      if type == "array" and length >= 2 then
        .[-2] as $c1 |
        .[-1] as $c2 |
        
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