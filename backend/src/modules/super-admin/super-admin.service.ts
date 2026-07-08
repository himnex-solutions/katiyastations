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
