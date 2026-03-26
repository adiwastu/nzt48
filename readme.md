NZT-48 Server Blueprint

The Config Files (The Brain and Memory)
These are all sitting in /etc/nzt48/

    file: .env

        what it does: this is your vault. it holds your telegram bot token.

    file: subscribers.txt

        what it does: the live database of chat ids. the main scanner reads this to know who to blast the alerts to. the listener script adds people here automatically when they hit /start.

    file: .tg_offset

        what it does: a tiny state tracker for the listener. it remembers the last telegram message id it processed so it doesn't spam people twice if the server restarts.

    directory: logs/

        what it does: stores the daily text files (e.g., 2026-03-26.log). acts as the permanent paper trail for every single 4-hour check, including dry runs.

The Telegram Commands (The Remote Control)
Sent directly to your bot via the Telegram app.

    /start

        what it does: registers your Chat ID to subscribers.txt and sends a welcome confirmation.

    /check

        what it does: asks the Linux systemd exactly how many hours/minutes are left until the next scheduled H4 scan.

    /health

        what it does: instantly pings all three of your MT5 bridge APIs (A, B, and C). replies with a clean status board showing if they are online, struggling, or dead, plus the current account balances.

    /logs

        what it does: reads today's log file from the server and dumps the entire text block right into the chat so you can verify the OHLC math without SSHing in.

The Core Engines (The Actual Bash Code)
These live in /usr/local/bin/

    file: nzt48.sh

        what it does: the master macro scanner. it wakes up, pulls the MT5 API data, writes to the daily log file, and calculates the engulfing patterns. it runs a silent "dry run" interceptor on minute 01, and executes the real live alert on minute 02.

    file: listener.sh

        what it does: the background daemon. it runs 24/7 doing long-polling against the telegram api to process your remote commands instantly.

    file: health_checker.sh

        what it does: the silent background monitor. it loops through your APIs checking for a valid balance response. it only speaks up and sends a telegram alert if an API is actually broken.

    file: imbalance.sh (and imbalance_refined.sh)

        what it does: the micro hunter scripts. if handoff is enabled, nzt48.sh passes the macro fibonacci zones here to scan the 15m internal structure.

The Systemd Automation (The Server Heartbeat)
These files live in /etc/systemd/system/

    file: nzt48.service

        what it does: tells the linux kernel exactly how to execute your main nzt48.sh script.

    file: nzt48.timer

        what it does: the master clock. it wakes up the nzt48.service at exactly minute :01 and :02 past your target H4 UTC hours (01, 05, 09, 13, 17, 21).

    file: health.service & health.timer

        what it does: runs the health_checker.sh script every 15 minutes (*:0/15) to ensure you don't go blind mid-session.

    file: listener.service

        what it does: keeps your listener.sh script running permanently in the background and restarts it automatically if it ever crashes.

File Tree Summary

Configs and Data:
/etc/nzt48/.env
/etc/nzt48/subscribers.txt
/etc/nzt48/.tg_offset
/etc/nzt48/logs/YYYY-MM-DD.log

Core Bash Scripts:
/usr/local/bin/nzt48.sh
/usr/local/bin/listener.sh
/usr/local/bin/health_checker.sh
/usr/local/bin/imbalance.sh
/usr/local/bin/imbalance_refined.sh

Systemd Automation:
/etc/systemd/system/nzt48.service
/etc/systemd/system/nzt48.timer
/etc/systemd/system/listener.service
/etc/systemd/system/health.service
/etc/systemd/system/health.timer

How to read today's logs manually from terminal:
cat /etc/nzt48/logs/$(date +"%Y-%m-%d").log