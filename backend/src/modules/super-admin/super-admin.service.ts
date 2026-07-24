import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';
import Redis from 'ioredis';
import { PrismaService } from '../../prisma/prisma.service';

const execAsync = promisify(exec);
const BACKUP_DIR = path.resolve(process.cwd(), 'backups');

/**
 * System-operations only — deliberately has zero access to financial or
 * personal data (billing, credit, reports, payroll, customers). See
 * BlockSuperAdminGuard, which is enforced on those modules instead of
 * this one, keeping the boundary explicit and centrally auditable.
 */
@Injectable()
export class SuperAdminService {
  private readonly logger = new Logger(SuperAdminService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {}

  async health() {
    let dbOk = true;
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      dbOk = false;
    }

    return {
      status: dbOk ? 'ok' : 'degraded',
      uptimeSeconds: Math.floor(process.uptime()),
      timestamp: new Date().toISOString(),
      database: dbOk ? 'connected' : 'unreachable',
    };
  }

  async redisStatus() {
    const client = new Redis({
      host: this.configService.get<string>('redis.host'),
      port: this.configService.get<number>('redis.port'),
      password: this.configService.get<string>('redis.password'),
      lazyConnect: true,
      connectTimeout: 3000,
    });

    try {
      await client.connect();
      const pong = await client.ping();
      const info = await client.info('memory');
      return { status: pong === 'PONG' ? 'connected' : 'unknown', info };
    } catch (error) {
      return { status: 'unreachable', error: (error as Error).message };
    } finally {
      client.disconnect();
    }
  }

  /** Structural counts only — no monetary values, matches the financial-data boundary. */
  async databaseStatus() {
    const [branches, users, tables, kots, menuItems, inventoryItems] = await Promise.all([
      this.prisma.branch.count(),
      this.prisma.user.count(),
      this.prisma.restaurantTable.count(),
      this.prisma.kot.count(),
      this.prisma.menuItem.count(),
      this.prisma.inventoryItem.count(),
    ]);

    return {
      connected: true,
      rowCounts: { branches, users, tables, kots, menuItems, inventoryItems },
    };
  }

  async containers() {
    try {
      const { stdout } = await execAsync('docker ps --format "{{json .}}"');
      const containers = stdout
        .trim()
        .split('\n')
        .filter(Boolean)
        .map((line) => JSON.parse(line));
      return { containers };
    } catch (error) {
      return { containers: [], error: 'Docker is not accessible from this process' };
    }
  }

  async logs(lines = 200) {
    const logPath = this.configService.get<string>('app.logFilePath') ?? '/var/log/katiya-station/api.log';
    if (!fs.existsSync(logPath)) {
      return { lines: [], message: `No log file found at ${logPath}` };
    }
    const content = fs.readFileSync(logPath, 'utf-8');
    return { lines: content.trim().split('\n').slice(-lines) };
  }

  async backup() {
    if (!fs.existsSync(BACKUP_DIR)) fs.mkdirSync(BACKUP_DIR, { recursive: true });

    const databaseUrl = this.configService.get<string>('database.url');
    if (!databaseUrl) throw new BadRequestException('DATABASE_URL is not configured');

    const filename = `backup-${new Date().toISOString().replace(/[:.]/g, '-')}.sql.gz`;
    const filePath = path.join(BACKUP_DIR, filename);

    try {
      await execAsync(`pg_dump "${databaseUrl}" | gzip > "${filePath}"`);
      return { filename, path: filePath };
    } catch (error) {
      this.logger.error(`Backup failed: ${(error as Error).message}`);
      throw new BadRequestException('Backup failed — check that pg_dump is installed on the server');
    }
  }

  /**
   * FRESH-START RESET for client handoff. Wipes all operational data (orders,
   * bills, payments, menu, tables, inventory, staff, logs, …) but KEEPS the
   * restaurant branch(es) and the super-admin account(s). Only rows are removed
   * — no schema change — so the app keeps running with no errors and the client
   * can create their own users and start clean.
   *
   * Takes an automatic safety backup first (best-effort). Requires the caller to
   * type the exact confirmation word, so it can never fire by accident.
   */
  async resetForHandoff(confirm: string) {
    if (confirm !== 'RESET') {
      throw new BadRequestException('Type RESET to confirm the reset.');
    }

    // Safety net: try to back up before wiping. Don't hard-block on a missing
    // pg_dump — the UI already warns and the operator confirmed — but report it.
    let backup: string | null = null;
    try {
      backup = (await this.backup()).filename;
    } catch (error) {
      this.logger.warn(`Pre-reset backup failed: ${(error as Error).message}`);
    }

    // Empty every table except branches, users and the migration history.
    // CASCADE clears FK children so order never matters; RESTART IDENTITY resets
    // any counters (fresh invoice/bill numbers).
    await this.prisma.$executeRawUnsafe(`
      DO $$
      DECLARE t text;
      BEGIN
        FOR t IN
          SELECT tablename FROM pg_tables
          WHERE schemaname = 'public'
            AND tablename NOT IN ('branches', 'users', '_prisma_migrations')
        LOOP
          EXECUTE format('TRUNCATE TABLE %I RESTART IDENTITY CASCADE', t);
        END LOOP;
      END $$;
    `);
    // Remove every user except the super admin(s).
    await this.prisma.$executeRawUnsafe(
      `DELETE FROM users WHERE role <> 'super_admin'`,
    );

    this.logger.warn('Fresh-start reset performed — kept branches + super-admin.');
    return { reset: true, backup };
  }

  async restore(filename: string) {
    const safeName = path.basename(filename); // no path traversal
    const filePath = path.join(BACKUP_DIR, safeName);
    if (!fs.existsSync(filePath)) throw new BadRequestException('Backup file not found');

    const databaseUrl = this.configService.get<string>('database.url');
    if (!databaseUrl) throw new BadRequestException('DATABASE_URL is not configured');

    try {
      await execAsync(`gunzip -c "${filePath}" | psql "${databaseUrl}"`);
      return { restored: true, filename: safeName };
    } catch (error) {
      this.logger.error(`Restore failed: ${(error as Error).message}`);
      throw new BadRequestException('Restore failed — check server logs for details');
    }
  }
}
