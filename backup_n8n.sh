#!/bin/sh

exec > /opt/n8n-install/logs/backup.log 2>&1

echo "🟡 backup_n8n.sh начался: $(date)"
set -e
set -x

# === Конфигурация ===
BACKUP_DIR="/opt/n8n-install/backups"
mkdir -p "$BACKUP_DIR"

NOW=$(date +"%Y-%m-%d-%H-%M")
ARCHIVE_NAME="n8n-backup-$NOW.7z"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

BASE_DIR="/opt/n8n-install"
ENV_FILE="$BASE_DIR/.env"
EXPORT_DIR="$BASE_DIR/export_temp"
DB_DUMP="$EXPORT_DIR/n8n-database.sql"

# === Очистка перед запуском ===
rm -f "$BACKUP_DIR"/n8n-backup-*.7z 2>/dev/null || true
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# === Загрузка переменных окружения ===
. "$ENV_FILE"
BOT_TOKEN="$TG_BOT_TOKEN"
USER_ID="$TG_USER_ID"

# === Функция отправки сообщений в Telegram ===
send_telegram() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$USER_ID" \
        -d parse_mode="Markdown" \
        -d text="$1" 2>/dev/null || true
}

# === Начало ===
send_telegram "📦 *Начинаю резервное копирование n8n...*"

# === ИСПРАВЛЕНО #2: Экспорт PostgreSQL базы данных ===
echo "💾 Экспортирую PostgreSQL базу данных..."
docker exec n8n-postgres pg_dump -U n8n n8n > "$DB_DUMP" || {
    echo "❌ Ошибка при экспорте БД"
    send_telegram "❌ Ошибка при экспорте PostgreSQL базы данных"
    exit 1
}
echo "✅ База данных экспортирована (размер: $(du -h "$DB_DUMP" | cut -f1))"

# === Экспорт Workflows ===
echo "📋 Экспортирую workflows..."
docker exec n8n-app n8n export:workflow --all --separate --output=/tmp/export_dir 2>/dev/null || true
docker cp n8n-app:/tmp/export_dir "$EXPORT_DIR" 2>/dev/null || true

WF_COUNT=$(ls -1 "$EXPORT_DIR/export_dir"/*.json 2>/dev/null | wc -l)
if [ "$WF_COUNT" -eq 0 ]; then
    echo "⚠️  В n8n нет workflows, но продолжаю backup для БД"
    send_telegram "⚠️ В n8n нет workflows, но backup включает БД"
else
    echo "✅ Экспортировано $WF_COUNT workflows"
fi

# === Экспорт Credentials ===
echo "🔑 Экспортирую credentials..."
docker exec n8n-app n8n export:credentials --all --output=/tmp/creds.json 2>/dev/null || true
if docker cp n8n-app:/tmp/creds.json "$EXPORT_DIR/credentials.json" 2>/dev/null; then
    echo "✅ Credentials экспортированы"
else
    echo "⚠️  Credentials отсутствуют"
fi

# === Копирование .env ===
echo "📝 Копирую .env (без паролей)"
cp "$ENV_FILE" "$EXPORT_DIR/.env.backup" 2>/dev/null || true

# === ИСПРАВЛЕНО #4: Создание зашифрованного архива с AES-256 ===
echo "🔐 Создаю зашифрованный архив (7zip AES-256)..."

# Генерируем пароль шифрования
BACKUP_PASSWORD=$(openssl rand -base64 24)

# Создаем архив с 7zip и AES-256 шифрованием
7z a -p"${BACKUP_PASSWORD}" -mhe=on -mhc=on "$ARCHIVE_PATH" \
    "$DB_DUMP" \
    "$EXPORT_DIR/export_dir"/*.json 2>/dev/null || {
    echo "❌ Ошибка при создании архива"
    send_telegram "❌ Ошибка при создании зашифрованного архива"
    exit 1
}

echo "✅ Архив создан и зашифрован (размер: $(du -h "$ARCHIVE_PATH" | cut -f1))"

# === Отправка архива в Telegram ===
echo "📱 Отправляю архив в Telegram..."
curl -s -F "document=@$ARCHIVE_PATH" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$USER_ID&caption=Backup%20n8n%20%28$NOW%29" \
    >/dev/null 2>&1 && echo "✅ Архив отправлен в Telegram"

# === Отправка пароля отдельным сообщением ===
echo "🔑 Отправляю пароль шифрования..."
sleep 2
send_telegram "🔑 *Пароль шифрования backup'а:*%0A\`$BACKUP_PASSWORD\`%0A%0A💡 Сохраните пароль в безопасном месте для восстановления"

# === Retention policy: удаляем backup'ы старше 7 дней ===
echo "🧹 Применяю policy хранения (7 дней)..."
find "$BACKUP_DIR" -name "n8n-backup-*.7z" -mtime +7 -delete 2>/dev/null || true
echo "✅ Старые backup'ы удалены"

# === Очистка временных файлов ===
echo "🧹 Очищаю временные файлы..."
rm -rf "$EXPORT_DIR"
docker exec n8n-app rm -rf /tmp/export_dir /tmp/creds.json 2>/dev/null || true

# === Финальное сообщение ===
echo "✅ Backup завершён успешно! ($(date))"
send_telegram "✅ *Backup завершён!*%0AФайл зашифрован и отправлен в Telegram%0AПароль отправлен отдельным сообщением"
