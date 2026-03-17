#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("USDJPY" "XAUUSD")
TIMEFRAME="H1" 

# Get current UTC hour to determine which broker's H4 just closed.
# (10# forces bash to read as base-10 so "09" doesn't throw an octal error)
HOUR_UTC=$(date -u +"%H")
CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")

# Calculate the 4-hour cycle modulo based on the UTC hour
MOD=$(( 10#$HOUR_UTC % 4 ))

# Name your brokers here based on the closing shift
if [ "$MOD" -eq 1 ]; then
    # 09:00 UTC / 4:00 PM WIB closes
    BROKER_NAME="OANDA/5ERS" 
elif [ "$MOD" -eq 2 ]; then
    # 10:00 UTC / 5:00 PM WIB closes (New York Close Standard)
    BROKER_NAME="TVC" 
else
    # Not a 4H close for our target brokers. Die silently. Zero CPU wasted.
    exit 0
fi

echo "[${CURRENT_TIME}] 4H Candle Closed for ${BROKER_NAME}. Scanning ${#SYMBOLS[@]} pairs..."

for SYMBOL in "${SYMBOLS[@]}"; do
    # Fetch 10 bars (we only need 8 for two H4 candles, plus a buffer)
    API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=${TIMEFRAME}&num_bars=10"
    RESPONSE=$(curl -s "$API_URL")

    if [ -z "$RESPONSE" ] || [ "$RESPONSE" == "null" ]; then
        echo "⚠️ Failed to fetch data for $SYMBOL"
        continue
    fi

    # Because we only run exactly when the 4H candle closes, we always 
    # just grab the immediate last 8 closed H1 bars (-9 to -1)
    RESULT=$(echo "$RESPONSE" | jq -r '
      if type == "array" and length >= 9 then
        
        (.[ -9 : -5 ]) as $c1_h1 |
        (.[ -5 : -1 ]) as $c2_h1 |
        
        {
          open:  $c1_h1[0].open,
          close: $c1_h1[-1].close,
          high:  ($c1_h1 | map(.high) | max),
          low:   ($c1_h1 | map(.low) | min)
        } as $c1 |

        {
          open:  $c2_h1[0].open,
          close: $c2_h1[-1].close,
          high:  ($c2_h1 | map(.high) | max),
          low:   ($c2_h1 | map(.low) | min)
        } as $c2 |
        
        if ($c1.close < $c1.open) and ($c2.close > $c2.open) and ($c2.open <= $c1.close) and ($c2.close > $c1.high) then
          "BULLISH \($c2.close)"
        elif ($c1.close > $c1.open) and ($c2.close < $c2.open) and ($c2.open >= $c1.close) and ($c2.close < $c1.low) then
          "BEARISH \($c2.close)"
        else
          "NONE 0"
        end

      else
        "ERROR 0"
      end
    ')

    read PATTERN PRICE <<< "$RESULT"

    if [ "$PATTERN" == "BULLISH" ]; then
        MESSAGE="🟢 ${SYMBOL}: ada bullish engulfing H4 di ${BROKER_NAME}. (price: ${PRICE})"

        # Broadcast loop
        while read -r ID; do
            [ -z "$ID" ] && continue
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${ID}" \
                -d text="${MESSAGE}" > /dev/null
        done < /etc/nzt48/subscribers.txt
            
        echo " -> 🟢 Broadcast sent: $MESSAGE"

    elif [ "$PATTERN" == "BEARISH" ]; then
        MESSAGE="🔴 ${SYMBOL}: ada bearish engulfing H4 di ${BROKER_NAME}. (price: ${PRICE})"

        # Broadcast loop
        while read -r ID; do
            [ -z "$ID" ] && continue
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${ID}" \
                -d text="${MESSAGE}" > /dev/null
        done < /etc/nzt48/subscribers.txt
            
        echo " -> 🔴 Broadcast sent: $MESSAGE"

    else
        # Catch-all for "NONE" or "ERROR"
        MESSAGE="⚪ ${SYMBOL}: ga ada engulfing H4 di ${BROKER_NAME}."

        # Broadcast loop
        while read -r ID; do
            [ -z "$ID" ] && continue
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${ID}" \
                -d text="${MESSAGE}" > /dev/null
        done < /etc/nzt48/subscribers.txt
            
        echo " -> ⚪ Broadcast checked: ga ada engulfing."
    fi
    
    sleep 1
done

echo "[$(date +"%Y-%m-%d %H:%M:%S %Z")] Cycle complete."