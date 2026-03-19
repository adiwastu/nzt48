#!/usr/bin/env bash

source /etc/nzt48/.env

# --- INCOMING ARGUMENTS FROM 15M SCRIPT ---
SYMBOL="$1"
PATTERN="$2"
C2_TIME="$3"
IMB15_LOW="$4"
IMB15_HIGH="$5"
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

echo "[REFINED ENGINE] Scanning 5m micro structure for ${SYMBOL}..."

# --- M5 EXTRACTION (49 bars to drop the baby candle) ---
API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=M5&num_bars=73"
M5_RESP=$(curl -s "$API_URL")

if [ -z "$M5_RESP" ] || [ "$M5_RESP" == "null" ]; then
    echo "⚠️ ${SYMBOL}: Failed to pull M5 data."
    exit 1
fi

# --- THE 5M REFINEMENT ENGINE (jq) ---
RESULT=$(echo "$M5_RESP" | jq -r --arg MACRO "$PATTERN" --arg IMB15_L "$IMB15_LOW" --arg IMB15_H "$IMB15_HIGH" '
  ($IMB15_L | tonumber) as $Z_LOW |
  ($IMB15_H | tonumber) as $Z_HIGH |
  
  if type == "array" and length >= 49 then
    .[0:48] | # Isolate the exact 48 M5 candles of the H4 block
    
    # Phase 1a: Find all directional 5m gaps
    [ range(0; length - 2) as $i |
      if $MACRO == "BULLISH" and .[$i].high < .[$i+2].low then
        { index: $i, low: .[$i].high, high: .[$i+2].low }
      elif $MACRO == "BEARISH" and .[$i].low > .[$i+2].high then
        { index: $i, low: .[$i+2].high, high: .[$i].low }
      else empty end
    ] |
    
    # Phase 1b: Merge consecutive 5m gaps into composites
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
    
    # Phase 2: The Overlap Filter (Must touch or exist inside the 15m Zone)
    # A gap overlaps the zone if its Low is <= Zone High AND its High is >= Zone Low
    map(select(.low <= $Z_HIGH and .high >= $Z_LOW)) |
    
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

read STATUS IMB5_LOW IMB5_HIGH <<< "$RESULT"

# --- PHASE 4: THE FINAL SNIPER OUTPUT ---
if [ "$STATUS" == "FOUND" ]; then
    if [ "$PATTERN" == "BULLISH" ]; then ICON="🟢"; else ICON="🔴"; fi
    
    MESSAGE="${ICON} ${SYMBOL} ${PATTERN} SNIPER SETUP
0.5 Fib Level: ${FIB}

🎯 15M Imbalance Zone: ${IMB15_LOW} to ${IMB15_HIGH}
🔬 REFINED 5M ENTRY: ${IMB5_LOW} to ${IMB5_HIGH}"

    send_alert "$MESSAGE"
else
    echo "⚪ ${SYMBOL}: 15m zone found, but NO 5m Imbalance overlapped it. Ignored."
fi