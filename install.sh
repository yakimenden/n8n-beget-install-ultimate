#!/bin/bash

set -euo pipefail

### Проверка прав
if (( EUID != 0 )); then
    echo "❗ Скрипт должен быть запущен от root: sudo bash <(curl ...)"
    exit 1
fi

clear

echo "🌐 Автоматическая установка n8n-BEGET Install ULTIMATE v2.0.2"
echo "========================================================"

### 1. Ввод переменных (минимум действий)
read -p "🌐 Введите домен для n8n (например: n8n.example.com): " DOMAIN
read -p "📧 Введите email для SSL-сертификата Let's Encrypt: " EMAIL
read -p "🔐 Введите пароль для базы данных Postgres (min 16 символов): " POSTGRES_PASSWORD
read -p "🤖 Введите Telegram Bot Token (@BotFather): " TG_BOT_TOKEN
read -p "👤 Введите Telegram User ID (@userinfobot): " TG_USER_ID
read -p "🗝️ Введите ключ шифрования n8n (Enter для автогенерации): " N8N_ENCRYPTION_KEY

if [ -z "${N8N_ENCRYPTION_KEY}" ]; then
    N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)"
    echo "✅ Сгенерирован ключ шифрования"
fi

### 2. Установка Docker и Compose
echo "📦 Проверка Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker compose &>/dev/null; then
    curl -sSL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || true
fi

### 3. Клонирование проекта с GitHub
echo "📥 Клонируем проект с GitHub v2.0.2..."
rm -rf /opt/n8n-install
git clone https://github.com/yakimenden/n8n-beget-install-ultimate.git /opt/n8n-install
cd /opt/n8n-install

### 4. Генерация .env файла
cat > ".env" << EOF
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_USER_ID=${TG_USER_ID}
DOCKER_GID=999
EOF

cat > "bot/.env" << EOF
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_USER_ID=${TG_USER_ID}
EOF

### 5. Создание необходимых директорий
mkdir -p /opt/n8n-install/{backups,logs,data}
touch /opt/n8n-install/logs/backup.log
touch /opt/n8n-install/logs/update.log

### 6. Установка прав на выполнение
chmod +x /opt/n8n-install/backup_n8n.sh
chmod +x /opt/n8n-install/update_n8n.sh

### 7. Запуск контейнеров
echo "🚀 Запускаю контейнеры Docker..."
docker compose up -d --build

echo "⏳ Ожидаю инициализацию сервисов (может занять до 2 минут)..."
sleep 120

### 8. Проверка статуса
echo "🩺 Проверка статуса контейнеров..."
docker ps

### 9. Настройка cron
echo "🔧 Устанавливаю cron-задачу на 02:00 UTC для автобэкапов..."
( crontab -l 2>/dev/null || true; \
echo "0 2 * * * /bin/bash /opt/n8n-install/backup_n8n.sh >> /opt/n8n-install/logs/backup.log 2>&1" \
) | crontab -

### 10. Уведомление в Telegram
curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TG_USER_ID}" \
  -d text="✅ Установка n8n-BEGET Install v2.0.2 завершена. Домен: https://${DOMAIN}" >/dev/null 2>&1 || true

### 11. Финальный вывод
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🎉 УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📌 Информация:"
echo "  🌐 Веб-интерфейс: https://${DOMAIN}"
echo "  🤖 Telegram бот: отправьте /start для помощи"
echo "  📅 Автобэкапы: ежедневно в 02:00 UTC"
echo "  📁 Проект: /opt/n8n-install"
echo ""
echo "🔧 Полезные команды:"
echo "  docker ps                              # Статус контейнеров"
echo "  docker logs -f n8n-app                 # Логи n8n"
echo "  cd /opt/n8n-install && docker compose restart  # Перезагрузить все"
echo "  bash /opt/n8n-install/backup_n8n.sh   # Ручной backup"
echo "  bash /opt/n8n-install/update_n8n.sh   # Обновить n8n (через Telegram)"
echo ""
echo "📚 Документация: https://github.com/yakimenden/n8n-beget-install-ultimate"
echo ""
echo "════════════════════════════════════════════════════════════════"
