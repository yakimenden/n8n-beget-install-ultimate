const TelegramBot = require('node-telegram-bot-api');
const { execSync, exec } = require('child_process');
const path = require('path');
const fs = require('fs');

// === Переменные окружения ===
const token = process.env.TG_BOT_TOKEN;
const userId = process.env.TG_USER_ID;

if (!token || !userId) {
    console.error("❌ Не заданы TG_BOT_TOKEN или TG_USER_ID!");
    process.exit(1);
}

const bot = new TelegramBot(token, { polling: true });

// === Проверка авторизации ===
function isAuthorized(msg) {
    return String(msg.chat.id) === String(userId);
}

// === Отправка сообщений ===
function send(text) {
    bot.sendMessage(userId, text, { parse_mode: 'Markdown' });
}

// === /start ===
bot.onText(/\/start/, (msg) => {
    if (!isAuthorized(msg)) return;
    send('🤖 *Доступные команды:*\n\n' +
        '/start — Эта справка\n' +
        '/status — Статус сервера\n' +
        '/logs — Логи n8n\n' +
        '/backups — Ручной backup\n' +
        '/update — Обновить n8n\n' +
        '/version — Версия n8n\n' +
        '/health — Проверка здоровья');
});

// === /status ===
bot.onText(/\/status/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const uptime = execSync('uptime -p').toString().trim();
        const containers = execSync('docker ps --format "{{.Names}} ({{.Status}})"').toString().trim();
        send(`🟢 *Сервер работает*\n⏱ Uptime: ${uptime}\n\n📦 *Контейнеры:*\n${containers}`);
    } catch (err) {
        send(`❌ Ошибка при получении статуса:\n\`${err.message}\``);
    }
});

// === /logs ===
bot.onText(/\/logs/, (msg) => {
    if (!isAuthorized(msg)) return;
    exec('docker logs --tail=100 n8n-app', (error, stdout, stderr) => {
        if (error) {
            send(`❌ Ошибка:\n\`${error.message}\``);
            return;
        }
        const MAX_LEN = 3900;
        if (stdout.length > MAX_LEN) {
            const logPath = '/tmp/n8n_logs.txt';
            fs.writeFileSync(logPath, stdout);
            bot.sendDocument(userId, logPath);
        } else {
            send(`📝 *Логи n8n:*\n\`\`\`\n${stdout}\n\`\`\``);
        }
    });
});

// === /backups ===
bot.onText(/\/backups/, (msg) => {
    if (!isAuthorized(msg)) return;
    send('📦 Запускаю резервное копирование...');
    exec('bash /opt/n8n-install/backup_n8n.sh', (error, stdout, stderr) => {
        if (error) {
            send(`❌ Ошибка backup'а:\n${error.message}`);
            return;
        }
        send('✅ Backup завершён!');
    });
});

// === /update ===
bot.onText(/\/update/, (msg) => {
    if (!isAuthorized(msg)) return;
    send('🔄 Начинаю обновление n8n...');
    exec('bash /update_n8n.sh', (error, stdout, stderr) => {
        if (error) {
            send(`❌ Ошибка обновления:\n${error.message}`);
            return;
        }
        send(`✅ Обновление завершено!`);
    });
});

// === /version ===
bot.onText(/\/version/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const version = execSync('docker exec n8n-app n8n --version').toString().trim();
        send(`🔹 *Версия n8n:* ${version}`);
    } catch (err) {
        send(`❌ Не удалось получить версию`);
    }
});

// === /health ===
bot.onText(/\/health/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const health = execSync('docker ps --format "{{.Names}} ({{.Status}})"').toString().trim();
        send(`🏥 *Статус сервисов:*\n${health}`);
    } catch (err) {
        send(`❌ Ошибка при проверке здоровья`);
    }
});

// === Обработчик ошибок ===
bot.on('polling_error', (error) => {
    console.error('Polling error:', error);
});

console.log('✅ Telegram Bot запущен и готов к использованию');
