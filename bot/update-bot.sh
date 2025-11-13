
update-bot-fix.sh
#!/bin/bash

set -e

echo "📥 Загружаем свежую версию bot.js из GitHub..."

curl -s -o /opt/n8n-install/bot/bot.js \
  https://raw.githubusercontent.com/yakimenden/n8n-beget-install-ultimate/main/bot/bot.js

echo "🔄 Перезапускаем бота..."

cd /opt/n8n-install
docker compose restart n8n-bot

echo "✅ Бот обновлён и перезапущен."