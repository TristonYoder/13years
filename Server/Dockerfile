FROM node:22-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src/ src/

FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

RUN addgroup --system --gid 1001 relay && adduser --system --uid 1001 relay

COPY --from=builder --chown=relay:relay /app/node_modules ./node_modules
COPY --from=builder --chown=relay:relay /app/src ./src
COPY --chown=relay:relay package.json ./

USER relay
EXPOSE 8080
ENV PORT=8080
ENV PLOTIPHAR_API_BASE=https://plotiphar.com

CMD ["node", "src/index.js"]
