#!/usr/bin/env bash

# --- LOAD SECRETS ---
source /etc/nzt48/.env

# --- CONFIG ---
SYMBOLS=("USDJPY" "XAUUSD")
TIMEFRAME="H4" 

CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S %Z")
echo "[${CURRENT_TIME}] V0.2: Scanning H4 Displacement..."

for SYMBOL in "${SYMBOLS[@]}"; do
    # Pull 3 bars to safely ignore the H4 baby candle
    API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=${SYMBOL}&timeframe=${TIMEFRAME}&num_bars=3"
    RESP=$(curl -s "$API_URL")

    if [ -z "$RESP" ] || [ "$RESP" == "null" ]; then
        continue
    fi

    RESULT=$(echo "$RESP" | jq -r '
      if type == "array" and length >= 3 then
        .[-3] as $c1 |
        .[-2] as $c2 |
        
        if ($c1.close < $c1.open) and ($c2.close > $c2.open) and ($c2.close > $c1.high) then
          "BULLISH \($c2.time) \($c2.low) \($c2.high)"
        elif ($c1.close > $c1.open) and ($c2.close < $c2.open) and ($c2.close < $c1.low) then
          "BEARISH \($c2.time) \($c2.low) \($c2.high)"
        else
          "NONE null 0 0"
        end
      else
        "NONE null 0 0"
      end
    ')

    read PATTERN T_DAY T_DATE T_MON T_YR T_HR T_TZ LOW HIGH <<< "$RESULT"

    if [ "$PATTERN" != "NONE" ]; then
        # Reconstruct the time string with spaces
        C2_TIME="${T_DAY} ${T_DATE} ${T_MON} ${T_YR} ${T_HR} ${T_TZ}"
        FIB=$(awk "BEGIN {print ($HIGH + $LOW) / 2}")
        
        echo "🔥 $PATTERN Displacement detected on $SYMBOL. Handing off to imbalance script..."
        
        # Fire and forget the Hunter script
        /usr/local/bin/imbalance.sh "$SYMBOL" "$PATTERN" "$C2_TIME" "$LOW" "$HIGH" "$FIB" &
    else
        echo "⚪ ${SYMBOL}: ga ada engulfing H4."
    fi
    sleep 1
done