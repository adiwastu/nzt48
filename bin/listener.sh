#!/usr/bin/env bash

source /etc/nzt48/.env
OFFSET_FILE="/etc/nzt48/.tg_offset"
SUBS_FILE="/etc/nzt48/subscribers.txt"

# Ensure offset file exists
touch $OFFSET_FILE

echo "Starting NZT-48 Telegram Listener..."

# Function to get the next scheduled run of nzt48.timer
get_next_scan() {
    local next_us=$(systemctl show nzt48.timer --property=NextElapseRealtime --value 2>/dev/null)
    if [ -z "$next_us" ] || [ "$next_us" = "0" ]; then
        echo "Timer not found or not scheduled."
        return
    fi
    # Convert microseconds to seconds
    local next_sec=$((next_us / 1000000))
    date -d "@$next_sec" +"%Y-%m-%d %H:%M:%S %Z"
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
                            -d text="✅ You are now taking NZT-48." > /dev/null
                        echo "New subscriber added: $CHAT_ID"
                    fi
                elif [ "$TEXT" = "/checknextscan" ]; then
                    NEXT_SCAN=$(get_next_scan)
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d chat_id="$CHAT_ID" \
                        -d text="📅 Next scheduled scan: $NEXT_SCAN" > /dev/null
                    echo "Replied to $CHAT_ID with next scan time."
                fi
            fi
        done
    fi
    # Sleep 1 second before asking again
    sleep 1
done