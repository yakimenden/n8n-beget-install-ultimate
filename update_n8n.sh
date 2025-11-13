#!/bin/bash

# ============================================================================
# update_n8n.sh - Обновление n8n с полным backup и очисткой системы
# Версия 2.0 (Production Ready)
# ============================================================================

### Защита от запуска из терминала (только через Telegram бот)
if [[ -t 0 ]]; then
    echo "🚫 Обновление можно запускать только через Telegram-бота!"
    exit 1
fi

# === Подключение переменных окружения ===
set -a
source /opt/n8n-install/.env
set +a

# === Глобальные переменные ===
LOG="/opt/n8n-install/logs/update.log"
TG_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"

### Функция уведомления в Telegram ===
notify() {
    local text="$1"
    curl -s -X POST "$TG_URL" \
        -d chat_id="$TG_USER_ID" \
        -d parse_mode="Markdown" \
        -d text="$text" >/dev/null 2>&1
}

### Обработчик ошибок ===
trap 'notify "❌ *ОШИБКА при обновлении n8n!*\nСм. лог: \`/opt/n8n-install/logs/update.log\`"' ERR

# === Логирование ===
mkdir -p "/opt/n8n-install/logs"
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "🟡 ==============================================================================="
echo "🟡 $(date '+%Y-%m-%d %H:%M:%S') - update_n8n.sh начался"
echo "🟡 ==============================================================================="
echo ""

notify "🔄 *Начинаю обновление n8n...*"

set -e
cd /opt/n8n-install

# === ШАГ 1: Создание backup ===
echo "📦 ШАГ 1: Создание backup перед обновлением..."
notify "📦 *Шаг 1:* создаю backup..."

bash /opt/n8n-install/backup_n8n.sh 2>&1 | tail -20

# === ШАГ 2: Проверка версий ===
echo ""
echo "🔍 ШАГ 2: Проверка версий n8n..."

CURRENT_VERSION=$(docker exec n8n-app n8n --version 2>/dev/null || echo "unknown")
echo "Текущая версия: $CURRENT_VERSION"

# Получаем последнюю версию из GitHub
LATEST_VERSION=$(curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest | grep '"tag_name":' | cut -d '"' -f 4 2>/dev/null || echo "unknown")
echo "Последняя версия: $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "✅ У вас уже последняя версия!"
    notify "✅ *У вас уже установлена последняя версия n8n:* $CURRENT_VERSION"
    exit 0
fi

echo "🆕 Доступна новая версия!"
notify "🔁 *Обновляю n8n с $CURRENT_VERSION на $LATEST_VERSION...*"

# === ШАГ 3: Остановка и удаление контейнера n8n ===
echo ""
echo "🛑 ШАГ 3: Остановка контейнера n8n..."

docker compose stop n8n 2>/dev/null || true
docker compose rm -f n8n 2>/dev/null || true
sleep 3

# === ШАГ 4: Пересборка контейнера n8n ===
echo "🔨 ШАГ 4: Пересборка контейнера n8n..."

docker compose build --no-cache n8n 2>&1 | grep -E "(Step|Successfully|error)" || true

# === ШАГ 5: Запуск обновленного контейнера ===
echo "🚀 ШАГ 5: Запуск обновленного контейнера..."

docker compose up -d n8n
sleep 10

# === ШАГ 6: Проверка статуса ===
echo "🩺 ШАГ 6: Проверка статуса контейнера..."

if ! docker ps | grep -q "n8n-app"; then
    echo "❌ Контейнер не запустился!"
    notify "❌ *Контейнер n8n не запустился после обновления!*"
    exit 1
fi

echo "✅ Контейнер запущен"

# === ШАГ 7: Проверка обновленной версии ===
echo "🔎 ШАГ 7: Проверка обновленной версии..."

sleep 5
NEW_VERSION=$(docker exec n8n-app n8n --version 2>/dev/null || echo "unknown")
echo "Новая версия: $NEW_VERSION"

if [ "$NEW_VERSION" = "$LATEST_VERSION" ] || [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    echo "✅ Версия обновлена успешно!"
else
    echo "⚠️  Версия может быть еще не готова, проверьте позже"
fi

# === ШАГ 8: Полная очистка системы ===
echo ""
echo "🧹 ШАГ 8: Очистка системы..."
notify "🧹 *Шаг 8:* очищаю систему от мусора..."

# Очистка apt
apt-get clean 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

# Очистка журналов
journalctl --vacuum-size=100M 2>/dev/null || true
journalctl --vacuum-time=7d 2>/dev/null || true

# Очистка логов
find /var/log -type f -name "*.gz" -delete 2>/dev/null || true
find /var/log -type f -name "*.log" -exec truncate -s 0 {} + 2>/dev/null || true

# Очистка Docker логов
find /var/lib/docker/containers/ -type f -name "*-json.log" -exec truncate -s 0 {} + 2>/dev/null || true

# Перезагрузка Docker (осторожно!)
systemctl restart docker 2>/dev/null || true

# Очистка неиспользуемых образов и контейнеров
docker image prune -f 2>/dev/null || true
docker builder prune -f 2>/dev/null || true
docker container prune -f 2>/dev/null || true
docker volume prune -f 2>/dev/null || true

# Статистика
echo ""
echo "📊 Использование диска:"
docker system df 2>/dev/null | head -5

echo ""
echo "💾 Партиция /:"
df -h / | sed -n '1,2p'

# === ФИНАЛ ===
echo ""
echo "🟢 ==============================================================================="
echo "✅ Обновление n8n завершено успешно! ($(date '+%Y-%m-%d %H:%M:%S'))"
echo "🟢 ==============================================================================="
echo ""

notify "✅ *Обновление n8n завершено!*\n🆕 Установлена версия: *$NEW_VERSION*\n✨ Система очищена и оптимизирована"
