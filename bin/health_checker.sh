#!/usr/bin/env bash

source /etc/nzt48/.env

# Format: "Nickname|URL"
APIS=(
    "5k|https://api.hotland3x3.my.id/account"
    "10k|https://api-5ers.hotland3x3.my.id/account"
    "100k|https://api-raven.hotland3x3.my.id/account"
)

ERROR_LOG=""

for entry in "${APIS[@]}"; do
    NICKNAME="${entry%%|*}"
    API_URL="${entry##*|}"
    
    # Super simple curl with a 15s timeout
    RESP=$(curl -s --max-time 15 "$API_URL")
    
    # Extract balance safely
    BALANCE=$(echo "$RESP" | jq -r '.data.balance // empty' 2>/dev/null)
    
    if [ -z "$BALANCE" ]; then
        SNIPPET="${RESP:0:40}"
        [ -z "$SNIPPET" ] && SNIPPET="(Empty Response)"
        
        ERROR_LOG="${ERROR_LOG}❌ ${NICKNAME}: Failed! Resp: ${SNIPPET}...
"
        echo "$(date): Health Check Failed - ${NICKNAME}"
    fi
done

# If ERROR_LOG is not empty, at least one API failed. Send the alert.
if [ -n "$ERROR_LOG" ]; then
    
    MSG="🚨 API HEALTH ALERT 🚨
One or more of your MT5 connections are down:

${ERROR_LOG}"

    while read -r ID; do
        [ -z "$ID" ] && continue
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${ID}" \
            -d text="${MSG}" > /dev/null
    done < /etc/nzt48/subscribers.txt
fi