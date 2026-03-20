#!/usr/bin/env bash

source /etc/nzt48/.env
OFFSET_FILE="/etc/nzt48/.tg_offset"
SUBS_FILE="/etc/nzt48/subscribers.txt"

# Ensure offset file exists
touch $OFFSET_FILE

echo "Starting NZT-48 Telegram Listener..."

# Function to get the next scheduled run of nzt48.timer with minutes left
get_next_scan() {
    local timer_line=$(systemctl list-timers nzt48.timer --no-legend 2>/dev/null | head -n1)
    if [ -z "$timer_line" ]; then
        echo "Timer not found or inactive."
        return
    fi

    local next_day=$(echo "$timer_line" | awk '{print $1}')
    local next_date=$(echo "$timer_line" | awk '{print $2}')
    local next_time=$(echo "$timer_line" | awk '{print $3}')
    local next_tz=$(echo "$timer_line" | awk '{print $4}')

    if [ -z "$next_day" ] || [ -z "$next_date" ] || [ -z "$next_time" ]; then
        echo "Could not parse next scan time."
        return
    fi

    # Build a date string that `date` can understand
    local datetime="${next_day} ${next_date} ${next_time} ${next_tz}"
    local next_epoch=$(date -d "$datetime" +%s 2>/dev/null)
    if [ -z "$next_epoch" ]; then
        echo "Could not convert time."
        return
    fi

    local now_epoch=$(date +%s)
    local diff=$((next_epoch - now_epoch))
    local minutes=$((diff / 60))
    local formatted=$(date -d "$datetime" +"%Y-%m-%d %H:%M:%S %Z")

    if [ $diff -lt 0 ]; then
        echo "Server OK. Next scheduled scan: ${formatted} (already passed, should fire soon?)"
    elif [ $minutes -lt 1 ]; then
        echo "Server OK. Next scheduled scan: ${formatted} (in less than a minute)"
    else
        echo "Server OK. Next scheduled scan: ${formatted} (in ${minutes} minutes)"
    fi
}

while true; do
    OFFSET=$(cat $OFFSET_FILE)
    [ -z "$OFFSET" ] && OFFSET=0

    # Ask Telegram if anyone sent a message (Wait up to 60 seconds)
    RESPONSE=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=60")

    # If the response contains actual messages
    if echo "$RESPONSE" | grep -q '"update_id"'; then

        # Get the highest update_id so we don't process these messages again
        NEW_OFFSET=$(echo "$RESPONSE" | jq '.result[-1].update_id')
        echo $((NEW_OFFSET + 1)) > $OFFSET_FILE

        # Process each update individually
        echo "$RESPONSE" | jq -c '.result[]' | while read -r UPDATE; do
            UPDATE_ID=$(echo "$UPDATE" | jq -r '.update_id')
            MESSAGE=$(echo "$UPDATE" | jq -r '.message')
            if [ "$MESSAGE" != "null" ]; then
                TEXT=$(echo "$MESSAGE" | jq -r '.text // empty')
                CHAT_ID=$(echo "$MESSAGE" | jq -r '.chat.id')
                
                if [ "$TEXT" = "/start" ]; then
                    # Add subscriber if not already present
                    if ! grep -q "^${CHAT_ID}$" "$SUBS_FILE"; then
                        echo "$CHAT_ID" >> "$SUBS_FILE"
                        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                            -d chat_id="$CHAT_ID" \
                            -d text="You are now taking NZT-48." > /dev/null
                        echo "New subscriber added: $CHAT_ID"
                    fi
                elif [ "$TEXT" = "/check" ]; then
                    NEXT_SCAN=$(get_next_scan)
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d chat_id="$CHAT_ID" \
                        -d text="$NEXT_SCAN" > /dev/null
                    echo "Replied to $CHAT_ID with next scan time."
                
                # --- NEW HEALTH COMMAND ---
                elif [ "$TEXT" = "/health" ]; then
                    API_URL="https://api.hotland3x3.my.id/fetch_data_pos?symbol=USDJPY&timeframe=H4&num_bars=1"
                    
                    # Ping the API and grab the HTTP status code (timeout 10s)
                    HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "$API_URL")
                    
                    if [ "$HTTP_STATUS" -eq 200 ]; then
                        MSG="🟢 API is ONLINE (HTTP 200 OK)"
                    elif [ "$HTTP_STATUS" -eq 000 ]; then
                        MSG="🔴 API is DOWN (Timeout/Unreachable)"
                    else
                        MSG="⚠️ API is STRUGGLING (HTTP $HTTP_STATUS)"
                    fi
                    
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d chat_id="$CHAT_ID" \
                        -d text="$MSG" > /dev/null
                    echo "Replied to $CHAT_ID with API health status."
                fi
            fi
        done
    fi
    # Sleep 1 second before asking again
    sleep 1
done