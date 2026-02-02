FROM node:22-alpine

WORKDIR /app

COPY external/grocery-sre-demo/src/web/package*.json ./
RUN npm install --omit=dev && npm audit fix --force || true

COPY external/grocery-sre-demo/src/web/ ./

EXPOSE 3000

CMD ["npm", "start"]
