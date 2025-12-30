FROM node:20-slim

# Install build dependencies for better-sqlite3
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create data directory for SQLite
RUN mkdir -p /app/data

COPY package*.json ./

RUN npm install --production

COPY bot.js ./

# Volume for persistent database
VOLUME ["/app/data"]

CMD ["node", "bot.js"]
