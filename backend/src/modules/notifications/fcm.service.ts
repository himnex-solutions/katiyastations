import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs';
import * as admin from 'firebase-admin';

/**
 * Thin wrapper around firebase-admin that no-ops when no service account
 * is configured, so the API keeps working before a real Firebase project
 * is wired up (see docs/VPS_DEPLOYMENT_GUIDE.md).
 */
@Injectable()
export class FcmService {
  private readonly logger = new Logger(FcmService.name);
  private app: admin.app.App | null = null;

  constructor(private readonly configService: ConfigService) {
    const path = this.configService.get<string>('FIREBASE_SERVICE_ACCOUNT_PATH');
    if (path && fs.existsSync(path)) {
      this.app = admin.initializeApp({
        credential: admin.credential.cert(JSON.parse(fs.readFileSync(path, 'utf-8'))),
      });
    } else {
      this.logger.warn('Firebase service account not configured — push notifications are disabled');
    }
  }

  async sendToTokens(tokens: string[], title: string, body: string) {
    if (!this.app || tokens.length === 0) return;
    try {
      await admin.messaging(this.app).sendEachForMulticast({
        tokens,
        notification: { title, body },
      });
    } catch (error) {
      this.logger.warn(`Failed to send push notification: ${(error as Error).message}`);
    }
  }
}
