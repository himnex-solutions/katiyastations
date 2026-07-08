import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
// The `minio` CommonJS build ships no usable type declarations (see
// src/types/minio.d.ts), so it's imported and used as `any` here.
import * as Minio from 'minio';
import { randomUUID } from 'crypto';

@Injectable()
export class MinioService implements OnModuleInit {
  private readonly logger = new Logger(MinioService.name);
  private client: any;
  private bucket: string;

  constructor(private readonly configService: ConfigService) {
    this.bucket = this.configService.get<string>('minio.bucket')!;
    this.client = new (Minio as any).Client({
      endPoint: this.configService.get<string>('minio.endPoint')!,
      port: this.configService.get<number>('minio.port'),
      useSSL: this.configService.get<boolean>('minio.useSSL'),
      accessKey: this.configService.get<string>('minio.accessKey'),
      secretKey: this.configService.get<string>('minio.secretKey'),
    });
  }

  async onModuleInit() {
    try {
      const exists = await this.client.bucketExists(this.bucket);
      if (!exists) {
        await this.client.makeBucket(this.bucket);
        await this.client.setBucketPolicy(
          this.bucket,
          JSON.stringify({
            Version: '2012-10-17',
            Statement: [
              {
                Effect: 'Allow',
                Principal: '*',
                Action: ['s3:GetObject'],
                Resource: [`arn:aws:s3:::${this.bucket}/*`],
              },
            ],
          }),
        );
      }
    } catch (error) {
      this.logger.warn(`MinIO not reachable at startup: ${(error as Error).message}`);
    }
  }

  async upload(buffer: Buffer, originalName: string, mimeType: string, folder = 'uploads'): Promise<string> {
    const extension = originalName.includes('.') ? originalName.split('.').pop() : 'bin';
    const objectName = `${folder}/${randomUUID()}.${extension}`;

    await this.client.putObject(this.bucket, objectName, buffer, buffer.length, {
      'Content-Type': mimeType,
    });

    const useSSL = this.configService.get<boolean>('minio.useSSL');
    const endPoint = this.configService.get<string>('minio.endPoint');
    const port = this.configService.get<number>('minio.port');
    return `${useSSL ? 'https' : 'http'}://${endPoint}:${port}/${this.bucket}/${objectName}`;
  }
}
