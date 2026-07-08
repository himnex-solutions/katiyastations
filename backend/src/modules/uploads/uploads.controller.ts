import {
  BadRequestException,
  Controller,
  Param,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { MinioService } from './minio.service';
import { PrismaService } from '../../prisma/prisma.service';

@Controller('uploads')
export class UploadsController {
  constructor(
    private readonly minioService: MinioService,
    private readonly prisma: PrismaService,
  ) {}

  @Post()
  @UseInterceptors(FileInterceptor('file'))
  async upload(@UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('No file uploaded');
    const url = await this.minioService.upload(file.buffer, file.originalname, file.mimetype);
    return { url };
  }

  @Post('menu-items/:itemId')
  @UseInterceptors(FileInterceptor('file'))
  async uploadMenuItemImage(@Param('itemId') itemId: string, @UploadedFile() file: Express.Multer.File) {
    if (!file) throw new BadRequestException('No file uploaded');
    const url = await this.minioService.upload(file.buffer, file.originalname, file.mimetype, 'menu-items');
    await this.prisma.menuItem.update({ where: { id: itemId }, data: { imageUrl: url } });
    return { url };
  }
}
