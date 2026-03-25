#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("XAUUSD")
TIMEFRAME="H4" 

# Set this to 'true' to chain scripts, or 'false' to just get a plain Telegram alert
ENABLE_HANDOFF=false

# Capture the exact minute the script was triggered
CURRENT_MIN=$(date +"%M")

CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")
echo "[${CURRENT_TIME}] V0.2: Scanning H4 Displacement..."

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
    # Pull 3 bars to safely ignore the H4 baby candle
    API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=${TIMEFRAME}&num_bars=3"
    RESP=$(curl -s "$API_URL")

    if [ -z "$RESP" ] || [ "$RESP" == "null" ]; then
        continue
    fi

    # Using '|' to separate outputs so we can cleanly extract OHLC data for both candles
    RESULT=$(echo "$RESP" | jq -r '
      if type == "array" and length >= 3 then
        .[-3] as $c1 |
        .[-2] as $c2 |
        
        if ($c1.close < $c1.open) and ($c2.close > $c2.open) and ($c2.close > $c1.high) then
          "BULLISH|\($c2.time)|\($c2.low)|\($c2.high)|\($c1.open)|\($c1.high)|\($c1.low)|\($c1.close)|\($c2.open)|\($c2.high)|\($c2.low)|\($c2.close)"
        elif ($c1.close > $c1.open) and ($c2.close < $c2.open) and ($c2.close < $c1.low) then
          "BEARISH|\($c2.time)|\($c2.low)|\($c2.high)|\($c1.open)|\($c1.high)|\($c1.low)|\($c1.close)|\($c2.open)|\($c2.high)|\($c2.low)|\($c2.close)"
        else
          "NONE|\($c2.time)|\($c2.low)|\($c2.high)|\($c1.open)|\($c1.high)|\($c1.low)|\($c1.close)|\($c2.open)|\($c2.high)|\($c2.low)|\($c2.close)"
        end
      else
        "NONE|null|0|0|0|0|0|0|0|0|0|0"
      end
    ')

    # Read all variables split by the '|' character
    IFS='|' read -r PATTERN C2_TIME LOW HIGH C1_O C1_H C1_L C1_C C2_O C2_H C2_L C2_C <<< "$RESULT"

    if [ "$PATTERN" != "NONE" ]; then
        FIB=$(awk "BEGIN {print ($HIGH + $LOW) / 2}")
        
        # --- LOGGING TO CONSOLE (ENGULFING FOUND) ---
        echo "🔥 $PATTERN Displacement detected on $SYMBOL."
        echo "   [Candle 1] O: $C1_O | H: $C1_H | L: $C1_L | C: $C1_C"
        echo "   [Candle 2] O: $C2_O | H: $C2_H | L: $C2_L | C: $C2_C"
        
        # --- THE FAKE RUN INTERCEPTOR ---
        # Checks if the current minute is 01 or 02 (to safely catch your first trigger)
        if [ "$CURRENT_MIN" == "01" ] || [ "$CURRENT_MIN" == "02" ]; then
            echo "   -> [FAKE RUN] Internal logic verified. Suppressing Telegram and Handoff."
        else
            # --- REAL RUN EXECUTION ---
            if [ "$ENABLE_HANDOFF" = true ]; then
                echo "   -> Handing off to imbalance script..."
                /usr/local/bin/imbalance.sh "$SYMBOL" "$PATTERN" "$C2_TIME" "$LOW" "$HIGH" "$FIB" &
            else
                echo "   -> Sending direct alert..."
                if [ "$PATTERN" == "BULLISH" ]; then ICON="🟢"; else ICON="🔴"; fi
                send_alert "${ICON}4H ${PATTERN} ENGULF ${SYMBOL} on OANDA"
            fi
        fi
        
    else
        # --- LOGGING TO CONSOLE (NO ENGULFING) ---
        echo "⚪ ${SYMBOL}: ga ada engulfing H4."
        # Only print the OHLC if we actually pulled valid data
        if [ "$C2_TIME" != "null" ]; then
            echo "   [Candle 1] O: $C1_O | H: $C1_H | L: $C1_L | C: $C1_C"
            echo "   [Candle 2] O: $C2_O | H: $C2_H | L: $C2_L | C: $C2_C"
        fi
    fi
    sleep 1
done