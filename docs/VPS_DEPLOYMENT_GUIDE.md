# Katiya Station RMS — VPS Deployment Guide

Target: Ubuntu 24.04 LTS, a rented VPS (2 vCPU / 4GB RAM minimum), and a
domain or subdomain pointed at the server (an IP-only setup works too —
see the note at the bottom).

## 1. Provision the server

1. Create the VPS (DigitalOcean, Hetzner, Vultr, etc.), Ubuntu 24.04 LTS.
2. Point a DNS A record at the VPS IP (e.g. `api.katiyastation.com`).
   If you don't have a domain yet, skip this and use the IP directly —
   `ApiConstants.baseUrl` in the Flutter app already supports either.

## 2. Firewall (UFW)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Do **not** open 5432 (Postgres), 6379 (Redis), 9000/9001 (MinIO), or 3000
(NestJS) to the public internet — docker-compose binds them to
`127.0.0.1` only; Nginx is the sole public entry point.

## 3. Fail2Ban

```bash
sudo apt update && sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

## 4. Docker & Docker Compose

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```

## 5. Clone the repo and configure

```bash
git clone <your-repo-url> katiya-station-rms
cd katiya-station-rms/backend
cp .env.example .env
nano .env   # fill in real secrets — see checklist below
```

`.env` checklist:
- `POSTGRES_PASSWORD`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
  `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` — generate with
  `openssl rand -hex 32` each, never reuse the example values.
- `CORS_ORIGIN` — set to your Flutter web origin, or `*` while testing.
- `SEED_SUPER_ADMIN_EMAIL` / `SEED_SUPER_ADMIN_PASSWORD` — change the
  password immediately after first login.

## 6. First boot

```bash
docker compose up -d postgres redis minio
docker compose run --rm nestjs_api npx prisma migrate dev --name init
docker compose run --rm nestjs_api npm run prisma:seed
docker compose up -d
docker compose ps
```

`prisma migrate dev` generates `backend/prisma/migrations/` from the
schema on its first run against a real database — commit that folder
to the repo afterwards so future deploys use `prisma migrate deploy`
(non-interactive, safe for CI) instead.

## 7. SSL via Certbot

```bash
sudo apt install -y certbot
sudo certbot certonly --webroot -w /var/www/certbot -d api.katiyastation.com
```

Update `backend/nginx.conf`'s `ssl_certificate` / `ssl_certificate_key`
paths to match the issued domain, then:

```bash
docker compose restart nginx
```

Add a renewal cron job:

```bash
echo "0 3 * * * certbot renew --quiet && docker compose -f /path/to/backend/docker-compose.yml restart nginx" | sudo tee -a /etc/crontab
```

## 8. Process management

Docker Compose's `restart: unless-stopped` (already set on every
service) handles process supervision and reboots — no separate PM2
layer is needed since everything runs inside containers.

## 9. Automated backups

Add a cron job that hits the super-admin backup endpoint (JWT-protected,
`super_admin` only) or runs `pg_dump` directly:

```bash
0 2 * * * docker exec $(docker compose -f /path/to/backend/docker-compose.yml ps -q postgres) \
  pg_dump -U katiya_user katiya_station_rms | gzip > /backups/katiya-$(date +\%F).sql.gz
```

Ship `/backups` offsite (rclone to S3/Backblaze, etc.) — see
`docs/DISASTER_RECOVERY.md`.

## 10. Log rotation

Docker's default `json-file` log driver grows unbounded. Add to
`/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

Then `sudo systemctl restart docker`.

## Pointing the Flutter app at your VPS

In `lib/core/constants/api_constants.dart`, either hardcode the
`defaultValue`s or pass at build time:

```bash
flutter build apk --dart-define=API_BASE_URL=https://api.katiyastation.com --dart-define=WS_BASE_URL=https://api.katiyastation.com
```

## IP-only setup (no domain yet)

Skip steps 1 and 7. Nginx's HTTP block still works over plain HTTP on
port 80; point the Flutter app at `http://<vps-ip>` instead of a
domain. Add HTTPS later without any backend code changes — only
`nginx.conf` and the Flutter base URL need to change.
