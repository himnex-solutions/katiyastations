# Katiya Station RMS — Disaster Recovery

## Backup strategy

- **Database**: nightly `pg_dump | gzip` (see `VPS_DEPLOYMENT_GUIDE.md`
  §9), retained locally for 14 days, shipped offsite daily.
- **Uploads (MinIO)**: `mc mirror` the bucket to an offsite S3-compatible
  target weekly (menu item photos are the only large binary asset;
  losing recent ones is low-impact, so weekly is sufficient).
- **Offsite target**: any S3-compatible bucket (Backblaze B2, AWS S3,
  another VPS running MinIO). Configure with `rclone config` and add:

```bash
0 3 * * * rclone copy /backups offsite-remote:katiya-station-backups --min-age 1h
```

## Point-in-time recovery procedure

1. Identify the most recent good backup: `ls -la /backups`.
2. Stop the API so nothing writes during restore:
   `docker compose stop nestjs_api`
3. Restore via the super-admin endpoint (`POST /super-admin/restore`,
   `{ "filename": "backup-2026-07-01T02-00-00.sql.gz" }`) or directly:

```bash
gunzip -c /backups/backup-<timestamp>.sql.gz | \
  docker exec -i $(docker compose ps -q postgres) psql -U katiya_user katiya_station_rms
```

4. Restart the API: `docker compose start nestjs_api`
5. Verify via `GET /super-admin/health` and `GET /super-admin/database`.

There is no WAL-archiving / continuous point-in-time recovery configured
by default — recovery granularity is "as of the last nightly dump."
If sub-24h RPO becomes a requirement, add `wal-g` or `pgbackrest` with
continuous WAL shipping to the same offsite bucket.

## Failover playbook

Single-VPS deployment has no automatic failover. In a full server loss:

1. Provision a new VPS, repeat `VPS_DEPLOYMENT_GUIDE.md` steps 1–5.
2. Restore the latest offsite `pg_dump` (step above) instead of running
   the seed script.
3. Restore the MinIO bucket: `mc mirror offsite-remote:katiya-station-backups/uploads minio/katiya-station-uploads`.
4. Repoint DNS at the new VPS IP.
5. Update the Flutter app's `API_BASE_URL` only if the domain changed;
   otherwise no client-side change is needed once DNS propagates.
