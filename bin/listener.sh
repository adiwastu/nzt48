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
        echo "Server OK. Next scheduled scan in less than a minute"
    elif [ $minutes -ge 60 ]; then
        local hours=$((minutes / 60))
        local rem_mins=$((minutes % 60))
        echo "Server OK. Next scheduled scan in ${hours}h ${rem_mins}m"
    else
        echo "Server OK. Next scheduled scan in ${minutes} minutes"
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
                            -d text="OANDA Gold H4 engulfing alert sudah live. Kirim /check untuk lihat kapan H4 berikutnya" > /dev/null
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
                    APIS=(
                        "A|https://api.hotland3x3.my.id/account"
                        "B|https://api-5ers.hotland3x3.my.id/account"
                        "C|https://api-raven.hotland3x3.my.id/account"
                    )
                    
                    # Start the message header
                    MSG="API status board:
"
                    
                    for entry in "${APIS[@]}"; do
                        NICKNAME="${entry%%|*}"
                        API_URL="${entry##*|}"
                        
                        RESP=$(curl -s --max-time 10 "$API_URL")
                        
                        if [ -z "$RESP" ]; then
                            MSG="${MSG}🔴 ${NICKNAME}: DOWN (Timeout)
"
                        elif ! echo "$RESP" | jq empty 2>/dev/null; then
                            MSG="${MSG}⚠️ ${NICKNAME}: STRUGGLING (Garbage JSON)
"
                        else
                            BALANCE=$(echo "$RESP" | jq -r '.data.balance // empty')
                            if [ -n "$BALANCE" ]; then
                                CURRENCY=$(echo "$RESP" | jq -r '.data.currency // "USD"')
                                MSG="${MSG}🟢 ${NICKNAME}: Ok
"
                            else
                                MSG="${MSG}⚠️ ${NICKNAME}: ONLINE (No)
"
                            fi
                        fi
                    done
                    
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d chat_id="$CHAT_ID" \
                        -d text="$MSG" > /dev/null
                    echo "Replied to $CHAT_ID with multi-API health status."
                
                # --- NEW LOGS COMMAND ---
                elif [ "$TEXT" = "/logs" ]; then
                    TODAY=$(date +"%Y-%m-%d")
                    LOG_FILE="/etc/nzt48/logs/${TODAY}.log"
                    
                    if [ -f "$LOG_FILE" ]; then
                        # Read the file and add a nice header
                        LOG_CONTENT=$(cat "$LOG_FILE")
                        MSG="📄 *Daily Engine Logs (${TODAY})*

${LOG_CONTENT}"
                    else
                        MSG="📭 No logs found for today (${TODAY}). The scanner hasn't run yet or the log directory is empty."
                    fi
                    
                    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                        -d chat_id="$CHAT_ID" \
                        -d text="$MSG" > /dev/null
                    echo "Replied to $CHAT_ID with today's logs."
                fi
            fi
        done
    fi
    # Sleep 1 second before asking again
    sleep 1
done