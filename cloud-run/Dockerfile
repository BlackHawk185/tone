FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY src/ ./src/

# Cloud Run sets PORT automatically; not used here but good practice
ENV NODE_ENV=production

CMD ["node", "src/index.js"]
