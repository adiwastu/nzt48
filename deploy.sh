#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run as root (sudo ./deploy.sh)"
  exit 1
fi

echo "🚀 Deploying NZT-48..."

echo "=> Pulling latest code..."
git pull origin main

echo "=> Installing bin..."
install -m 755 bin/nzt48.sh /usr/local/bin/nzt48.sh
install -m 755 bin/listener.sh /usr/local/bin/listener.sh
install -m 755 bin/imbalance.sh /usr/local/bin/imbalance.sh
install -m 755 bin/imbalance_refined.sh /usr/local/bin/imbalance_refined.sh
install -m 755 bin/health_checker.sh /usr/local/bin/health_checker.sh

echo "=> Installing systemd..."
install -m 644 systemd/nzt48.service /etc/systemd/system/
install -m 644 systemd/nzt48.timer /etc/systemd/system/
install -m 644 systemd/listener.service /etc/systemd/system/
install -m 644 systemd/health.service /etc/systemd/system/
install -m 644 systemd/health.timer /etc/systemd/system/

echo "=> Reloading daemon..."
systemctl daemon-reload

echo "=> Starting timers & listener..."
systemctl enable nzt48.timer
systemctl restart nzt48.timer
systemctl enable health.timer
systemctl restart health.timer
systemctl enable listener.service
systemctl restart listener.service

echo "✅ NZT-48 is live."