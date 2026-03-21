#!/usr/bin/env bash

source /etc/nzt48/.env

API_URL="https://api.hotland3x3.my.id/account"

# Super simple curl
RESP=$(curl -s "$API_URL")

# Extract balance safely from inside the 'data' wrapper
BALANCE=$(echo "$RESP" | jq -r '.data.balance // empty' 2>/dev/null)

if [ -z "$BALANCE" ]; then
    
    SNIPPET="${RESP:0:60}"
    [ -z "$SNIPPET" ] && SNIPPET="(Empty Response)"
    
    MSG="🚨 HEALTH CHECK FAILED 🚨
Your MT5 API is reachable, but the /account endpoint failed!
Response: ${SNIPPET}..."

    while read -r ID; do
        [ -z "$ID" ] && continue
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${ID}" \
            -d text="${MSG}" > /dev/null
    done < /etc/nzt48/subscribers.txt
    
    echo "$(date): Health Check Failed - Account Balance Missing"
fi