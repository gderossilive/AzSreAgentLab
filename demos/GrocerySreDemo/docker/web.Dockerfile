FROM node:20-alpine

WORKDIR /app

COPY external/grocery-sre-demo/src/web/package*.json ./
RUN npm install --omit=dev

COPY external/grocery-sre-demo/src/web/ ./

EXPOSE 3000

CMD ["npm", "start"]
