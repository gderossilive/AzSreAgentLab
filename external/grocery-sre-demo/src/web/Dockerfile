FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production && npm audit fix --force || true

COPY . .

EXPOSE 3000

CMD ["npm", "start"]
