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

echo "[IMBALANCE ENGINE] Scanning 15m internal structure for ${SYMBOL}..."

# --- M15 EXTRACTION ---
API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=M15&num_bars=17"
M15_RESP=$(curl -s "$API_URL")

if [ -z "$M15_RESP" ] || [ "$M15_RESP" == "null" ]; then
    echo "⚠️ ${SYMBOL}: Failed to pull M15 data."
    exit 1
fi

# --- THE IMBALANCE ENGINE (jq) ---
RESULT=$(echo "$M15_RESP" | jq -r --arg MACRO "$PATTERN" --arg FIB_STR "$FIB" '
  ($FIB_STR | tonumber) as $FIB |
  
  if type == "array" and length >= 17 then
    .[0:16] | # Isolate the exact 16 candles of the H4 block
    
    # Phase 1a: Find all directional gaps
    [ range(0; length - 2) as $i |
      if $MACRO == "BULLISH" and .[$i].high < .[$i+2].low then
        { index: $i, low: .[$i].high, high: .[$i+2].low }
      elif $MACRO == "BEARISH" and .[$i].low > .[$i+2].high then
        { index: $i, low: .[$i+2].high, high: .[$i].low }
      else empty end
    ] |
    
    # Phase 1b: Merge consecutive gaps into composites
    reduce .[] as $gap (
      [];
      if length == 0 then [$gap]
      else
        .[-1] as $last |
        if $gap.index == $last.index + 1 then
          .[0:-1] + [{
            index: $gap.index,
            low: (if $last.low < $gap.low then $last.low else $gap.low end),
            high: (if $last.high > $gap.high then $last.high else $gap.high end)
          }]
        else
          . + [$gap]
        end
      end
    ) |
    
    # Phase 2: The Fib Filter
    map(select(
      ($MACRO == "BULLISH" and .low <= $FIB) or
      ($MACRO == "BEARISH" and .high >= $FIB)
    )) |
    
    # Phase 3: The Deepest Extractor
    if length == 0 then
      "NONE 0 0"
    else
      if $MACRO == "BULLISH" then
        min_by(.low) | "FOUND \(.low) \(.high)"
      else
        max_by(.high) | "FOUND \(.low) \(.high)"
      end
    end
    
  else
    "NONE 0 0"
  end
')

read STATUS IMB_LOW IMB_HIGH <<< "$RESULT"

# --- PHASE 4: THE HANDOFF ---
if [ "$STATUS" == "FOUND" ]; then
    echo "🎯 15m Imbalance confirmed. Handing off to 5m Refinement..."
    /usr/local/bin/imbalance_refined.sh "$SYMBOL" "$PATTERN" "$C2_TIME" "$IMB_LOW" "$IMB_HIGH" "$FIB" &
else
    echo "⚪ ${SYMBOL}: H4 Engulfing found, but NO 15m Imbalance reached the Fib zone. Ignored."
fi