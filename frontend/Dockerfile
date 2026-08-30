# public-app Dockerfile
FROM node:20-alpine

WORKDIR /app

# Layer caching: install deps before copying app code
COPY ./src/package*.json ./
RUN npm install --omit=dev

COPY index.js ./

EXPOSE 3000

CMD ["node", "index.js"]