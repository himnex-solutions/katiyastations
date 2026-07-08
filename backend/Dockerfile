# ============================================================
# KATIYA STATION RMS — BACKEND DOCKERFILE
# Multi-stage build: compile TypeScript, then run on a slim image
# ============================================================

FROM node:20-alpine AS builder
WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci

COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

# pg_dump/psql needed by the super-admin backup/restore endpoints
RUN apk add --no-cache postgresql-client

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev && npx prisma generate

COPY --from=builder /app/dist ./dist

EXPOSE 3000
CMD ["node", "dist/main.js"]
