# private-app Dockerfile
FROM node:20-alpine

WORKDIR /app
RUN apk add --no-cache curl

# Layer caching: install deps before copying app code
COPY package*.json ./
RUN npm install --omit=dev

COPY src/ ./

EXPOSE 3000

CMD ["node", "index.js"]