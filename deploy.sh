#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run as root (sudo ./deploy.sh)"
  exit 1
fi

echo "🚀 Deploying NZT-48..."

echo "=> Pulling latest code..."
git pull origin main

echo "=> Installing bin..."
cp bin/nzt48.sh /usr/local/bin/nzt48.sh
chmod +x /usr/local/bin/nzt48.sh
cp bin/listener.sh /usr/local/bin/listener.sh
chmod +x /usr/local/bin/listener.sh

echo "=> Installing systemd..."
cp systemd/nzt48.service /etc/systemd/system/
cp systemd/nzt48.timer /etc/systemd/system/
cp systemd/listener.service /etc/systemd/system/

echo "=> Reloading daemon..."
systemctl daemon-reload

echo "=> Starting timer..."
systemctl enable nzt48.timer
systemctl restart nzt48.timer
systemctl enable listener.service
systemctl restart listener.service

echo "✅ NZT-48 is live."