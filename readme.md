nzt-48 server blueprint

the config files (the brain and memory)
these are all sitting in /etc/nzt48/

file: .env
what it does: this is your vault. it holds your telegram bot token.

file: subscribers.txt
what it does: the live database of chat ids. the main scanner reads this to know who to blast the alerts to. the listener script adds people here automatically when they hit start.

file: .tg_offset
what it does: a tiny state tracker for the listener. it remembers the last telegram message id it processed so it doesnt spam people twice if the server restarts.

the core engines (the actual bash code)
these live in /usr/local/bin/

file: nzt48.sh
what it does: the main scanner. it wakes up, checks the modulo math against the utc hour, pulls the api data, calculates the engulfing patterns, broadcasts to the subscriber list, and dies instantly to save cpu.

file: listener.sh
what it does: the background daemon. it runs 24/7 doing long-polling. if someone texts your bot /start, it grabs their id, adds it to the subscribers text file, and sends them a welcome message.

the systemd automation (the server heartbeat)
these files live in /etc/systemd/system/

file: nzt48.service
what it does: tells the linux kernel exactly how to execute your main nzt48.sh script.

file: nzt48.timer
what it does: the master clock. it wakes up the nzt48.service at exactly minute 01 of every single hour.

file: listener.service
what it does: keeps your listener.sh script running permanently in the background and restarts it automatically if it ever crashes.

configs and data
/etc/nzt48/.env
/etc/nzt48/subscribers.txt
/etc/nzt48/.tg_offset

core bash scripts
/usr/local/bin/nzt48.sh
/usr/local/bin/listener.sh

systemd automation
/etc/systemd/system/nzt48.service
/etc/systemd/system/nzt48.timer
/etc/systemd/system/listener.service


how to read
cat /etc/nzt48/logs/$(date +"%Y-%m-%d").log