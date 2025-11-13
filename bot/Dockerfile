```dockerfile
FROM node:20-alpine

WORKDIR /app

# Устанавливаем необходимые пакеты
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    postgresql-client \
    jq

# Копируем зависимости
COPY package*.json ./

# Устанавливаем npm пакеты
RUN npm install --production

# Копируем исходники бота
COPY bot.js .

# Запускаем бота
CMD ["node", "bot.js"]
```

---
