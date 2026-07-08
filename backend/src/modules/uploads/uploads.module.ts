import { Module } from '@nestjs/common';
import { UploadsController } from './uploads.controller';
import { MinioService } from './minio.service';

@Module({
  controllers: [UploadsController],
  providers: [MinioService],
  exports: [MinioService],
})
export class UploadsModule {}
