#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("XAUUSD")
TIMEFRAME="H4" 

# Set this to 'true' to chain scripts, or 'false' to just get a plain Telegram alert
ENABLE_HANDOFF=false

# --- LOGGING SETUP ---
LOG_DIR="/etc/nzt48/logs"
mkdir -p "$LOG_DIR" # Ensure the folder exists
TODAY=$(date +"%Y-%m-%d")
LOG_FILE="${LOG_DIR}/${TODAY}.log"

# Capture the exact minute the script was triggered
CURRENT_MIN=$(date +"%M")
CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")

# Determine if this is the Dry Run or the Real Run
if [ "$CURRENT_MIN" == "01" ]; then
    RUN_TYPE="DRY RUN"
else
    RUN_TYPE="REAL RUN"
fi

echo "[$CURRENT_TIME] V0.3: Scanning H4 Displacement ($RUN_TYPE)..."

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

    # --- FORMAT DAILY LOG ENTRY ---
    if [ "$PATTERN" == "BULLISH" ]; then STATUS="🟢 BULLISH ENGULFING"
    elif [ "$PATTERN" == "BEARISH" ]; then STATUS="🔴 BEARISH ENGULFING"
    else STATUS="⚪ NO ENGULFING"; fi

    # Write the beautifully formatted block to today's text file
    echo "--------------------------------------------------------------------------------" >> "$LOG_FILE"
    echo "TIME     : ${CURRENT_TIME} [${RUN_TYPE}]" >> "$LOG_FILE"
    echo "SYMBOL   : ${SYMBOL}" >> "$LOG_FILE"
    echo "STATUS   : ${STATUS}" >> "$LOG_FILE"
    if [ "$C2_TIME" != "null" ]; then
        echo "CANDLE 1 : O: $C1_O | H: $C1_H | L: $C1_L | C: $C1_C" >> "$LOG_FILE"
        echo "CANDLE 2 : O: $C2_O | H: $C2_H | L: $C2_L | C: $C2_C" >> "$LOG_FILE"
    else
        echo "CANDLE   : NO VALID DATA RETURNED" >> "$LOG_FILE"
    fi
    echo "--------------------------------------------------------------------------------" >> "$LOG_FILE"


    # --- EXECUTE LOGIC ---
    if [ "$PATTERN" != "NONE" ]; then
        FIB=$(awk "BEGIN {print ($HIGH + $LOW) / 2}")
        
        # Logging to Console
        echo "🔥 $PATTERN Displacement detected on $SYMBOL."
        echo "   [Candle 1] O: $C1_O | H: $C1_H | L: $C1_L | C: $C1_C"
        echo "   [Candle 2] O: $C2_O | H: $C2_H | L: $C2_L | C: $C2_C"
        
        # The Interceptor
        if [ "$RUN_TYPE" == "DRY RUN" ]; then
            echo "   -> [FAKE RUN] Internal logic verified. Suppressing Telegram and Handoff."
        else
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
        # Logging to Console (No Engulfing)
        echo "⚪ ${SYMBOL}: ga ada engulfing H4."
        if [ "$C2_TIME" != "null" ]; then
            echo "   [Candle 1] O: $C1_O | H: $C1_H | L: $C1_L | C: $C1_C"
            echo "   [Candle 2] O: $C2_O | H: $C2_H | L: $C2_L | C: $C2_C"
        fi
    fi
    sleep 1
done