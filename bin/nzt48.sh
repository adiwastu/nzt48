#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("USDJPY" "XAUUSD" "GBPJPY" "BTCUSD")
TIMEFRAME="H1" 
CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")

# The only two H4 grids that actually matter in global Forex.
# Assuming your API natively provides one of these at Offset 0, the other is exactly 2 hours shifted.
declare -A BROKERS=(
    ["NY_CLOSE"]=0
    ["UTC_MIDNIGHT"]=2
)

echo "[${CURRENT_TIME}] Firing up NZT-48..."
echo "-> Scanning ${#SYMBOLS[@]} pairs across the two primary global H4 grids."

for SYMBOL in "${SYMBOLS[@]}"; do
    # Fetch 12 H1 bars once per symbol to save API calls
    API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=${TIMEFRAME}&num_bars=12"
    RESPONSE=$(curl -s "$API_URL")

    if [ -z "$RESPONSE" ] || [ "$RESPONSE" == "null" ]; then
        echo "⚠️ Failed to fetch H1 data for $SYMBOL"
        continue
    fi

    # Loop through the two configured broker layouts
    for BROKER_NAME in "${!BROKERS[@]}"; do
        OFFSET=${BROKERS[$BROKER_NAME]}

        RESULT=$(echo "$RESPONSE" | jq -r --argjson off "$OFFSET" '
          if type == "array" and length >= 10 then
            
            # Construct Candle 1 (Previous 4H) and Candle 2 (Just Closed 4H)
            (.[ (-9 - $off) : (-5 - $off) ]) as $c1_h1 |
            (.[ (-5 - $off) : (-1 - $off) ]) as $c2_h1 |
            
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
            
            # Strict Engulfing Rules
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
            MESSAGE="🟢 <b>${SYMBOL} H4 engulfing found on ${BROKER_NAME} grid!</b>
<b>Time:</b> ${CURRENT_TIME}
<b>Pattern:</b> Strict Bullish
<b>Price:</b> ${PRICE}"

            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${TELEGRAM_CHAT_ID}" \
                -d text="${MESSAGE}" \
                -d parse_mode="HTML" > /dev/null
                
            echo " -> 🟢 BULLISH alert sent for ${SYMBOL} on ${BROKER_NAME}."

        elif [ "$PATTERN" == "BEARISH" ]; then
            MESSAGE="🔴 <b>${SYMBOL} H4 engulfing found on ${BROKER_NAME} grid!</b>
<b>Time:</b> ${CURRENT_TIME}
<b>Pattern:</b> Strict Bearish
<b>Price:</b> ${PRICE}"

            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="${TELEGRAM_CHAT_ID}" \
                -d text="${MESSAGE}" \
                -d parse_mode="HTML" > /dev/null
                
            echo " -> 🔴 BEARISH alert sent for ${SYMBOL} on ${BROKER_NAME}."
        fi
    done
    
    # 1 second breather between symbols so your Flask API doesn't choke
    sleep 1
done

echo "[$(date +"%Y-%m-%d %H:%M:%S %Z")] NZT-48 cycle complete."