# BenchLog sync server. No npm dependencies: node:sqlite is built in.
#
# Build:  docker build -t benchlog-server .
# Run:    docker run -d --name benchlog --restart unless-stopped -p 8420:8420 -v benchlog-data:/data benchlog-server
# Token:  docker logs benchlog   (printed once, on first start; also in /data/token)

FROM node:24-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
ENV PORT=8420 DATA_DIR=/data NODE_ENV=production
VOLUME ["/data"]
EXPOSE 8420
USER node
HEALTHCHECK --interval=60s --timeout=5s CMD wget -qO- http://127.0.0.1:8420/v1/health || exit 1
CMD ["node", "src/main.js"]
