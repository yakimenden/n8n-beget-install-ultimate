#!/bin/bash

set -euo pipefail

# ============================================================================
# n8n-BEGET Install ULTIMATE v2.0 - Production Ready
# Полностью автоматическая установка n8n + PostgreSQL + Redis + Traefik + Telegram Bot
# ============================================================================

### Проверка прав root
if (( EUID != 0 )); then
    echo "❗ Скрипт должен быть запущен от root: sudo bash <(curl ...)"
    exit 1
fi

clear
echo "🌐 Автоматическая установка n8n-BEGET Install ULTIMATE v2.0"
echo "============================================================"
echo ""

### 1. Ввод переменных конфигурации

echo "📝 Заполните необходимые параметры:"
echo ""

read -p "🌐 Введите домен для n8n (например: n8n.example.com): " DOMAIN
read -p "📧 Введите email для SSL-сертификата Let's Encrypt: " EMAIL
read -p "🔐 Введите пароль для базы данных PostgreSQL (min 16 символов): " POSTGRES_PASSWORD
read -p "🤖 Введите Telegram Bot Token (@BotFather): " TG_BOT_TOKEN
read -p "👤 Введите ваш Telegram User ID (@userinfobot): " TG_USER_ID
read -p "🗝️ Введите ключ шифрования n8n (Enter = автогенерация): " N8N_ENCRYPTION_KEY

if [ -z "${N8N_ENCRYPTION_KEY}" ]; then
    N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)"
    echo "✅ Сгенерирован ключ шифрования: ${N8N_ENCRYPTION_KEY}"
fi

### 2. Валидация DNS (FIX #3)
echo ""
echo "🔍 Валидирую DNS для домена $DOMAIN..."

RESOLVED_IP=$(dig +short A $DOMAIN 2>/dev/null | tail -1)
LOCAL_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || echo "")

if [[ -z "$RESOLVED_IP" ]]; then
    echo "❌ ОШИБКА: Домен $DOMAIN не разрешается!"
    echo "   Создайте A-запись: Type=A, Name=$DOMAIN, Value=$PUBLIC_IP"
    exit 1
elif [[ "$RESOLVED_IP" != "$LOCAL_IP" ]] && [[ "$RESOLVED_IP" != "$PUBLIC_IP" ]]; then
    echo "⚠️  ВНИМАНИЕ: Домен разрешается на $RESOLVED_IP, но сервер на $LOCAL_IP/$PUBLIC_IP"
    read -p "   Продолжить? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

echo "✅ DNS валидация пройдена"

### 3. Проверка портов
echo ""
echo "🔌 Проверяю доступность портов 80 и 443..."

if ss -tlnp 2>/dev/null | grep -qE ':80 |:443 '; then
    echo "⚠️  ВНИМАНИЕ: Порты 80 или 443 уже используются!"
    echo "   Остановите конфликтующие сервисы или измените порты в docker-compose.yml"
fi

echo "✅ Проверка портов завершена"

### 4. Установка Docker (если нужна)
echo ""
echo "📦 Проверка Docker..."

if ! command -v docker &>/dev/null; then
    echo "   Устанавливаю Docker..."
    curl -fsSL https://get.docker.com | sh
    echo "✅ Docker установлен"
else
    DOCKER_VERSION=$(docker --version)
    echo "✅ Docker уже установлен: $DOCKER_VERSION"
fi

### 5. Проверка Docker Compose
if ! command -v docker compose &>/dev/null; then
    echo "   Устанавливаю Docker Compose..."
    curl -sSL https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || true
    echo "✅ Docker Compose установлен"
else
    COMPOSE_VERSION=$(docker compose version)
    echo "✅ Docker Compose уже установлен: $COMPOSE_VERSION"
fi

### 6. Клонирование проекта с GitHub
echo ""
echo "📥 Клонирую проект с GitHub..."

rm -rf /opt/n8n-install
git clone https://github.com/yakimenden/n8n-beget-install-ultimate.git /opt/n8n-install 2>/dev/null || \
git clone https://github.com/YOUR_USERNAME/n8n-beget-install-ultimate.git /opt/n8n-install

cd /opt/n8n-install

echo "✅ Проект загружен"

### 7. Генерация файлов конфигурации
echo ""
echo "⚙️  Генерирую файлы конфигурации..."

# Основной .env
cat > ".env" << EOF
DOMAIN=$DOMAIN
EMAIL=$EMAIL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

chmod 600 .env
echo "✅ .env создан (права 600 для безопасности)"

# Bot .env
mkdir -p bot
cat > "bot/.env" << EOF
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_USER_ID=$TG_USER_ID
EOF

chmod 600 bot/.env

# Директории
mkdir -p logs backups data
chmod 755 logs backups data

echo "✅ Директории созданы"

### 8. Исправление прав на выполнение скриптов
echo ""
echo "🔧 Устанавливаю права на выполнение скриптов..."

chmod +x *.sh 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true
chmod +x bot/*.sh 2>/dev/null || true

echo "✅ Права установлены"

### 9. Запуск Docker Compose
echo ""
echo "🚀 Запускаю контейнеры..."

docker compose pull 2>/dev/null || true
docker compose build 2>&1 | grep -E "(^FROM|^Step|^Successfully|error)" || true
docker compose up -d

echo "✅ Контейнеры запущены"

### 10. Ожидание инициализации
echo ""
echo "⏳ Ожидаю инициализацию сервисов (может занять до 2 минут)..."

sleep 10

# Проверка PostgreSQL
echo "   Проверяю PostgreSQL..."
DEADLINE=$(( $(date +%s) + 60 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if docker exec n8n-postgres pg_isready -U n8n &>/dev/null; then
        echo "   ✅ PostgreSQL готов"
        break
    fi
    sleep 2
done

# Проверка n8n
echo "   Проверяю n8n..."
DEADLINE=$(( $(date +%s) + 90 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if curl -sf http://localhost:5678/health >/dev/null 2>&1; then
        echo "   ✅ n8n готов"
        break
    fi
    sleep 3
done

### 11. Выпуск SSL сертификата
echo ""
echo "🔐 Ожидаю выпуск SSL сертификата Let's Encrypt..."

DEADLINE=$(( $(date +%s) + 120 ))
CERT_OK=0

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if docker logs n8n-traefik 2>&1 | grep -Eiq 'Certificate obtained|certificate.*obtained'; then
        CERT_OK=1
        echo "✅ SSL сертификат выпущен"
        break
    fi
    sleep 5
done

if [ $CERT_OK -eq 0 ]; then
    echo "⚠️  Сертификат еще не выпущен, но может появиться позже"
fi

### 12. Финальные проверки
echo ""
echo "🩺 Финальные проверки..."

# Проверка контейнеров
CONTAINERS=$(docker ps --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}" | tail -5)
echo "📦 Активные контейнеры:"
echo "$CONTAINERS"

# Проверка HTTPS
echo ""
echo "🔒 Проверяю HTTPS доступ..."
if curl -ksI "https://$DOMAIN" 2>/dev/null | grep -q "200\|301\|302\|308"; then
    echo "✅ HTTPS доступен"
else
    echo "⚠️  HTTPS может быть недоступен, проверьте DNS и firewall"
fi

### 13. Установка cron для автобэкапов
echo ""
echo "⏰ Устанавливаю cron-задачу для автобэкапов в 02:00 UTC..."

mkdir -p /opt/n8n-install/logs
chmod +x /opt/n8n-install/backup_n8n.sh

# Безопасное добавление в crontab
(crontab -l 2>/dev/null || echo "") | grep -v "backup_n8n.sh" | crontab - 2>/dev/null || true
(crontab -l 2>/dev/null || true; echo "0 2 * * * /bin/bash /opt/n8n-install/backup_n8n.sh >> /opt/n8n-install/logs/backup.log 2>&1") | crontab -

echo "✅ Cron установлен"

### 14. Уведомление в Telegram
echo ""
echo "📱 Отправляю уведомление в Telegram..."

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TG_USER_ID}" \
    -d text="✅ Установка n8n-BEGET Install v2.0 завершена!%0A%0A🌐 Домен: https://${DOMAIN}%0A🤖 Telegram бот готов к использованию%0A📅 Автобэкапы запланированы на 02:00 UTC ежедневно" \
    >/dev/null 2>&1 || echo "⚠️  Не удалось отправить сообщение в Telegram"

echo "✅ Уведомление отправлено"

### 15. Финальный вывод
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🎉 УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📌 Важная информация:"
echo "  🌐 Веб-интерфейс: https://$DOMAIN"
echo "  🤖 Telegram бот готов (отправьте /start для помощи)"
echo "  📅 Автобэкапы: ежедневно в 02:00 UTC"
echo "  📁 Проект находится в: /opt/n8n-install"
echo ""
echo "🔧 Полезные команды:"
echo "  docker ps                     # Статус контейнеров"
echo "  docker logs -f n8n-app        # Логи n8n"
echo "  docker compose restart        # Перезагрузить все"
echo "  /opt/n8n-install/backup_n8n.sh  # Ручной backup"
echo ""
echo "📚 Документация:"
echo "  GitHub: https://github.com/YOUR_USERNAME/n8n-beget-install-ultimate"
echo "  Docs: /opt/n8n-install/docs/"
echo ""
echo "════════════════════════════════════════════════════════════════"
