FROM node:20-alpine

WORKDIR /app

COPY external/grocery-sre-demo/src/api/package*.json ./
RUN npm install --omit=dev

COPY external/grocery-sre-demo/src/api/ ./

EXPOSE 3100

CMD ["npm", "start"]
