#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("USDJPY" "XAUUSD")

# Get current UTC hour to determine which broker's H4 just closed.
HOUR_UTC=$(date -u +"%H")
CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")
MOD=$(( 10#$HOUR_UTC % 4 ))

if [ "$MOD" -eq 1 ]; then
    BROKER_NAME="OANDA/5ERS" 
elif [ "$MOD" -eq 2 ]; then
    BROKER_NAME="TVC" 
else
    exit 0
fi

echo "[${CURRENT_TIME}] 4H Candle Closed for ${BROKER_NAME}. Initiating Fractal Scan..."

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

# --- JQ COMPOSITE FVG ENGINES ---
# These engines dynamically merge contiguous gaps and filter by overlap

JQ_BULLISH_FVG='
  if type == "array" and length >= $min_len then
    (.[ -($min_len) : -1 ]) | 
    reduce range(0; length - 2) as $i (
      {groups: [], curr: null};
      if (.[$i].high < .[$i+2].low) then
        if .curr == null then .curr = {bot: .[$i].high, top: .[$i+2].low, end: $i}
        elif $i == .curr.end + 1 then .curr.end = $i | .curr.top = .[$i+2].low
        else .groups += [.curr] | .curr = {bot: .[$i].high, top: .[$i+2].low, end: $i}
        end
      else
        if .curr != null then .groups += [.curr] | .curr = null else . end
      end
    ) |
    (if .curr != null then .groups += [.curr] else . end) |
    .groups | 
    map(select(.top >= ($aoi_bot|tonumber) and .bot <= ($aoi_top|tonumber))) |
    if length > 0 then
      "VALID \((map(.bot) | min)) \((map(.top) | max))"
    else
      "NONE"
    end
  else
    "NONE"
  end
'

JQ_BEARISH_FVG='
  if type == "array" and length >= $min_len then
    (.[ -($min_len) : -1 ]) | 
    reduce range(0; length - 2) as $i (
      {groups: [], curr: null};
      if (.[$i].low > .[$i+2].high) then
        if .curr == null then .curr = {bot: .[$i+2].high, top: .[$i].low, end: $i}
        elif $i == .curr.end + 1 then .curr.end = $i | .curr.bot = .[$i+2].high
        else .groups += [.curr] | .curr = {bot: .[$i+2].high, top: .[$i].low, end: $i}
        end
      else
        if .curr != null then .groups += [.curr] | .curr = null else . end
      end
    ) |
    (if .curr != null then .groups += [.curr] else . end) |
    .groups | 
    map(select(.top >= ($aoi_bot|tonumber) and .bot <= ($aoi_top|tonumber))) |
    if length > 0 then
      "VALID \((map(.bot) | min)) \((map(.top) | max))"
    else
      "NONE"
    end
  else
    "NONE"
  end
'

# --- MAIN LOOP ---
for SYMBOL in "${SYMBOLS[@]}"; do
    
    # --- PHASE 1: MACRO H4 SCAN ---
    API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=H1&num_bars=10"
    H1_RESP=$(curl -s "$API_URL")

    if [ -z "$H1_RESP" ] || [ "$H1_RESP" == "null" ]; then
        continue
    fi

    # Extract H4 Engulfing + The High and Low of Candle 2
    H4_RESULT=$(echo "$H1_RESP" | jq -r '
      if type == "array" and length >= 8 then
        
        # 1. Calculate the native MT5 4-Hour block epoch for each candle
        map(. + {
          h4_epoch: (
            (.time | sub(" GMT$"; "") | strptime("%a, %d %b %Y %H:%M:%S") | mktime) - 
            (((.time[17:19] | tonumber) % 4) * 3600)
          )
        }) |
        
        # 2. Group them together chronologically
        group_by(.h4_epoch) | sort_by(.[0].h4_epoch) |
        
        # 3. If the last group has less than 3 candles, it is a brand new forming hour. Drop it.
        if (.[-1] | length) < 3 then .[:-1] else . end |
        
        # 4. Grab the last two fully formed H4 blocks
        if length >= 2 then
          .[-2] as $c1_h1 |
          .[-1] as $c2_h1 |
          
          { open: $c1_h1[0].open, close: $c1_h1[-1].close, high: ($c1_h1 | map(.high) | max), low: ($c1_h1 | map(.low) | min) } as $c1 |
          { open: $c2_h1[0].open, close: $c2_h1[-1].close, high: ($c2_h1 | map(.high) | max), low: ($c2_h1 | map(.low) | min) } as $c2 |
          
          # Notice we also loosened the Open gap rule ($c2.open < $c1.open) to prevent spread traps
          if ($c1.close < $c1.open) and ($c2.close > $c2.open) and ($c2.open < $c1.open) and ($c2.close > $c1.high) then
            "BULLISH \($c2.low) \($c2.high)"
          elif ($c1.close > $c1.open) and ($c2.close < $c2.open) and ($c2.open > $c1.open) and ($c2.close < $c1.low) then
            "BEARISH \($c2.low) \($c2.high)"
          else
            "NONE 0 0"
          end
        else
          "NONE 0 0"
        end
      else
        "NONE 0 0"
      end
    ')

    read PATTERN C2_LOW C2_HIGH <<< "$H4_RESULT"

    # ==========================================
    # BULLISH GAUNTLET
    # ==========================================
    if [ "$PATTERN" == "BULLISH" ]; then
        # Define Area of Interest (Diskon = Low to Midpoint)
        MIDPOINT=$(awk "BEGIN {print ($C2_HIGH + $C2_LOW) / 2}")
        
        # --- PHASE 2: M15 SCAN ---
        M15_RESP=$(curl -s "https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=M15&num_bars=17")
        M15_RES=$(echo "$M15_RESP" | jq -r --argjson min_len 17 --arg aoi_bot "$C2_LOW" --arg aoi_top "$MIDPOINT" "$JQ_BULLISH_FVG")
        read M15_STATUS M15_BOT M15_TOP <<< "$M15_RES"

        if [ "$M15_STATUS" != "VALID" ]; then
            send_alert "🟡 ${SYMBOL}: ada engulfing h4 bullish. tapi di area diskon ga ada 15m imbalance. thank you next"
            continue
        fi

        # --- PHASE 3: M5 SCAN ---
        # 4 hours = 48 M5 candles (+1 for buffer = 49). We use M15_BOT and M15_TOP as the new AOI.
        M5_RESP=$(curl -s "https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=M5&num_bars=49")
        M5_RES=$(echo "$M5_RESP" | jq -r --argjson min_len 49 --arg aoi_bot "$M15_BOT" --arg aoi_top "$M15_TOP" "$JQ_BULLISH_FVG")
        read M5_STATUS M5_BOT M5_TOP <<< "$M5_RES"

        if [ "$M5_STATUS" != "VALID" ]; then
            send_alert "🟠 ${SYMBOL}: ada engulfing h4 bullish, di area diskon, ada 15m imbalance. tapi ga ada 5m imbalance... thank you next"
            continue
        fi

        # --- GOLDEN SETUP ---
        send_alert "🟢 ${SYMBOL}: ada engulfing h4 bullish, di area diskon, ada 15m imbalance. ada 5m imbalance yang overlap. BUY!!"

    # ==========================================
    # BEARISH GAUNTLET
    # ==========================================
    elif [ "$PATTERN" == "BEARISH" ]; then
        # Define Area of Interest (Premium = Midpoint to High)
        MIDPOINT=$(awk "BEGIN {print ($C2_HIGH + $C2_LOW) / 2}")
        
        # --- PHASE 2: M15 SCAN ---
        M15_RESP=$(curl -s "https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=M15&num_bars=17")
        M15_RES=$(echo "$M15_RESP" | jq -r --argjson min_len 17 --arg aoi_bot "$MIDPOINT" --arg aoi_top "$C2_HIGH" "$JQ_BEARISH_FVG")
        read M15_STATUS M15_BOT M15_TOP <<< "$M15_RES"

        if [ "$M15_STATUS" != "VALID" ]; then
            send_alert "🟡 ${SYMBOL}: ada engulfing h4 bearish. tapi di area premium ga ada 15m imbalance. thank you next"
            continue
        fi

        # --- PHASE 3: M5 SCAN ---
        M5_RESP=$(curl -s "https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=M5&num_bars=49")
        M5_RES=$(echo "$M5_RESP" | jq -r --argjson min_len 49 --arg aoi_bot "$M15_BOT" --arg aoi_top "$M15_TOP" "$JQ_BEARISH_FVG")
        read M5_STATUS M5_BOT M5_TOP <<< "$M5_RES"

        if [ "$M5_STATUS" != "VALID" ]; then
            send_alert "🟠 ${SYMBOL}: ada engulfing h4 bearish, di area premium, ada 15m imbalance. tapi ga ada 5m imbalance... thank you next"
            continue
        fi

        # --- GOLDEN SETUP ---
        send_alert "🔴 ${SYMBOL}: ada engulfing h4 bearish, di area premium, ada 15m imbalance. ada 5m imabalance yang overlap. SELL!!"

    # ==========================================
    # NO ENGULFING (HEARTBEAT)
    # ==========================================
    else
        send_alert "⚪ ${SYMBOL}: ga ada engulfing H4 di ${BROKER_NAME}."
    fi
    
    sleep 1
done

echo "[$(date +"%Y-%m-%d %H:%M:%S %Z")] Cycle complete."