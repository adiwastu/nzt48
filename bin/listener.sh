#!/usr/bin/env bash

source /etc/nzt48/.env
OFFSET_FILE="/etc/nzt48/.tg_offset"
SUBS_FILE="/etc/nzt48/subscribers.txt"

# Ensure offset file exists
touch $OFFSET_FILE

echo "Starting NZT-48 Telegram Listener..."

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

        # Extract the IDs of people who specifically typed /start
        IDS=$(echo "$RESPONSE" | jq -r '.result[] | select(.message.text == "/start") | .message.chat.id')

        for ID in $IDS; do
            # If they aren't already in the file, add them
            if ! grep -q "^${ID}$" "$SUBS_FILE"; then
                echo "$ID" >> "$SUBS_FILE"
                
                # Send them a confirmation message
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d chat_id="$ID" \
                    -d text="✅ You are now taking NZT-48." > /dev/null
                    
                echo "New subscriber added: $ID"
            fi
        done
    fi
    # Sleep 1 second before asking again
    sleep 1
done