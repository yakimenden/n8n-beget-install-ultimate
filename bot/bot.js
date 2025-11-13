const TelegramBot = require('node-telegram-bot-api');
const { execSync, exec } = require('child_process');
const path = require('path');
const fs = require('fs');

// === Переменные окружения ===
const token = process.env.TG_BOT_TOKEN;
const userId = process.env.TG_USER_ID;

if (!token || !userId) {
    console.error("❌ Не заданы необходимые переменные окружения TG_BOT_TOKEN и TG_USER_ID");
    process.exit(1);
}

const bot = new TelegramBot(token, { polling: true });
console.log("✅ Telegram-бот запущен");

// === Функции ===
function isAuthorized(msg) {
    return String(msg.chat.id) === String(userId);
}

function send(text, options = {}) {
    const defaultOptions = { parse_mode: 'Markdown', ...options };
    bot.sendMessage(userId, text, defaultOptions).catch(err => {
        console.error('Ошибка при отправке сообщения:', err.message);
    });
}

function sendDocument(filePath, caption) {
    if (!fs.existsSync(filePath)) {
        send(`❌ Файл не найден: ${filePath}`);
        return;
    }
    bot.sendDocument(userId, filePath, { caption }).catch(err => {
        console.error('Ошибка при отправке файла:', err.message);
    });
}

// === /start — Справка по командам ===
bot.onText(/\/start/, (msg) => {
    if (!isAuthorized(msg)) return;
    send(`🤖 *n8n Admin Bot v2.0*\n\n📋 *Доступные команды:*\n\n` +
        `🔍 /status — Статус контейнеров и сервера\n` +
        `📝 /logs — Последние логи n8n\n` +
        `💾 /backup — Создать резервную копию\n` +
        `📤 /backups — Список всех бэкапов\n` +
        `🔄 /update — Обновить n8n\n` +
        `🐳 /docker — Статус Docker контейнеров\n` +
        `🔐 /health — Проверка здоровья сервиса\n` +
        `💾 /disk — Использование дискового пространства\n` +
        `📊 /memory — Использование памяти\n` +
        `⚙️ /version — Версия n8n`
    );
});

// === /status — Статус контейнеров ===
bot.onText(/\/status/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const uptime = execSync('uptime -p').toString().trim();
        const containers = execSync('docker ps --format "table {{.Names}}\t{{.Status}}"').toString().trim();
        send(`🟢 *Сервер работает*\n\n⏱ Uptime: ${uptime}\n\n📦 *Контейнеры:*\n\`\`\`\n${containers}\n\`\`\``);
    } catch (err) {
        send(`❌ Ошибка при получении статуса:\n\`\`\`\n${err.message}\n\`\`\``);
    }
});

// === /logs — Логи n8n ===
bot.onText(/\/logs/, (msg) => {
    if (!isAuthorized(msg)) return;
    exec('docker logs --tail=200 n8n-app 2>&1', (error, stdout, stderr) => {
        if (error) {
            send(`❌ Ошибка получения логов:\n\`\`\`\n${error.message}\n\`\`\``);
            return;
        }

        const MAX_LEN = 4000;
        if (stdout.length > MAX_LEN) {
            // Очень длинные логи отправляем файлом
            const logPath = '/tmp/n8n_logs.txt';
            fs.writeFileSync(logPath, stdout);
            sendDocument(logPath, '📝 Логи n8n (последние 200 строк)');
        } else {
            send(`📝 *Логи n8n (последние 200 строк):*\n\`\`\`\n${stdout}\n\`\`\``);
        }
    });
});

// === /backup — Ручной бэкап ===
bot.onText(/\/backup/, (msg) => {
    if (!isAuthorized(msg)) return;
    send('📦 *Запускаю резервное копирование...*');
    
    const backupScript = '/opt/n8n-install/backup_n8n.sh';
    exec(`bash ${backupScript}`, { timeout: 600000 }, (error, stdout, stderr) => {
        if (error) {
            send(`❌ Ошибка при бэкапе:\n\`\`\`\n${error.message}\n\`\`\``);
            return;
        }
        send(`✅ *Бэкап завершён*\n\n${stdout}`);
    });
});

// === /backups — Список бэкапов ===
bot.onText(/\/backups/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const backupDir = '/opt/n8n-install/backups';
        if (!fs.existsSync(backupDir)) {
            send('❌ Директория бэкапов не найдена');
            return;
        }

        const files = fs.readdirSync(backupDir)
            .filter(f => f.endsWith('.zip'))
            .sort()
            .reverse()
            .slice(0, 10);

        if (files.length === 0) {
            send('📭 Нет бэкапов');
            return;
        }

        let text = '📦 *Последние бэкапы:*\n\n';
        files.forEach((f, i) => {
            const size = (fs.statSync(path.join(backupDir, f)).size / 1024 / 1024).toFixed(2);
            text += `${i + 1}. ${f} (${size} MB)\n`;
        });
        send(text);
    } catch (err) {
        send(`❌ Ошибка:\n\`\`\`\n${err.message}\n\`\`\``);
    }
});

// === /update — Обновление n8n ===
bot.onText(/\/update/, (msg) => {
    if (!isAuthorized(msg)) return;
    send('🔄 *Начинаю обновление n8n...*\n\nСначала создам бэкап, потом обновлю...');

    // Сначала бэкап
    exec('bash /opt/n8n-install/backup_n8n.sh', { timeout: 600000 }, (error) => {
        if (error) {
            send(`⚠️ Ошибка при создании бэкапа: ${error.message}`);
            return;
        }

        send('✅ Бэкап создан. Начинаю обновление...');

        // Потом обновление
        exec('cd /opt/n8n-install && docker compose pull && docker compose up -d --build', 
            { timeout: 900000 }, (error, stdout, stderr) => {
                if (error) {
                    send(`❌ Ошибка при обновлении:\n\`\`\`\n${error.message}\n\`\`\``);
                    return;
                }
                send(`✅ *Обновление завершено!*\n\nДождитесь инициализации контейнеров (1-2 минуты)`);
        });
    });
});

// === /docker — Статус Docker ===
bot.onText(/\/docker/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const ps = execSync('docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"').toString();
        const stats = execSync('docker stats --no-stream --format "{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"').toString();
        send(`🐳 *Docker Статус:*\n\n*Контейнеры:*\n\`\`\`\n${ps}\n\`\`\`\n\n*Ресурсы:*\n\`\`\`\n${stats}\n\`\`\``);
    } catch (err) {
        send(`❌ Ошибка:\n\`\`\`\n${err.message}\n\`\`\``);
    }
});

// === /health — Проверка здоровья ===
bot.onText(/\/health/, (msg) => {
    if (!isAuthorized(msg)) return;
    exec('curl -s http://localhost:5678/health', (error, stdout) => {
        if (error) {
            send(`❌ n8n недоступен: ${error.message}`);
            return;
        }
        try {
            const health = JSON.parse(stdout);
            send(`✅ *n8n работает*\n\n${JSON.stringify(health, null, 2)}`);
        } catch {
            send(`⚠️ Неожиданный ответ:\n\`\`\`\n${stdout}\n\`\`\``);
        }
    });
});

// === /disk — Дисковое пространство ===
bot.onText(/\/disk/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const disk = execSync('df -h /opt/n8n-install').toString();
        const dockerSpace = execSync('du -sh /var/lib/docker 2>/dev/null || echo "0 /var/lib/docker"').toString();
        send(`💾 *Дисковое пространство:*\n\`\`\`\n${disk}\n\nn8n-install:\\n${dockerSpace}\n\`\`\``);
    } catch (err) {
        send(`❌ Ошибка:\n\`\`\`\n${err.message}\n\`\`\``);
    }
});

// === /memory — Память ===
bot.onText(/\/memory/, (msg) => {
    if (!isAuthorized(msg)) return;
    try {
        const free = execSync('free -h').toString();
        send(`📊 *Использование памяти:*\n\`\`\`\n${free}\n\`\`\``);
    } catch (err) {
        send(`❌ Ошибка:\n\`\`\`\n${err.message}\n\`\`\``);
    }
});

// === /version — Версия n8n ===
bot.onText(/\/version/, (msg) => {
    if (!isAuthorized(msg)) return;
    exec('docker exec n8n-app n8n --version', (error, stdout) => {
        if (error) {
            send(`❌ Не удалось получить версию: ${error.message}`);
            return;
        }
        send(`📌 *Версия n8n:* ${stdout.trim()}`);
    });
});

// === Обработка неизвестных команд ===
bot.on('message', (msg) => {
    if (!msg.text.startsWith('/')) return;
    if (!isAuthorized(msg)) {
        send('❌ Доступ запрещён');
        return;
    }
    send('❓ Неизвестная команда. Напишите /start для справки');
});

// === Обработка ошибок ===
bot.on('polling_error', (error) => {
    console.error('Polling error:', error.message);
});

console.log('✅ Бот полностью инициализирован');
