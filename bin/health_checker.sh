#!/usr/bin/env bash

source /etc/nzt48/.env

API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=USDJPY&timeframe=H4&num_bars=1"

# Check the HTTP status code
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" --max-time 15 "$API_URL")

if [ "$HTTP_STATUS" -ne 200 ]; then
    MSG="🚨 HEALTH CHECK FAILED 🚨
Your MT5 API is currently unresponsive!
HTTP Status: ${HTTP_STATUS}"

    # Broadcast to all subscribers
    while read -r ID; do
        [ -z "$ID" ] && continue
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${ID}" \
            -d text="${MSG}" > /dev/null
    done < /etc/nzt48/subscribers.txt
    
    echo "$(date): Health Check Failed ($HTTP_STATUS)"
fi