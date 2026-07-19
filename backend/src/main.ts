import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const config = app.get(ConfigService);

  // Behind Nginx: trust the first proxy hop so req.ip is the real client IP
  // (used by rate limiting and recorded in audit logs), not the proxy's.
  app.set('trust proxy', 1);

  app.use(helmet());
  app.enableCors({
    origin: config.get<string>('app.corsOrigin'),
    credentials: true,
  });

  app.setGlobalPrefix(config.get<string>('app.apiPrefix') ?? 'api/v1');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true, // strip unknown properties instead of rejecting them
      transform: true,
      forbidUnknownValues: false,
    }),
  );

  app.useGlobalFilters(new GlobalExceptionFilter());

  const swaggerConfig = new DocumentBuilder()
    .setTitle('Katiya Station RMS API')
    .setDescription('Self-hosted restaurant management system backend')
    .setVersion('1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('docs', app, document);

  const port = config.get<number>('app.port') ?? 3000;
  await app.listen(port, '0.0.0.0');
  // eslint-disable-next-line no-console
  console.log(`Katiya Station RMS API running on port ${port}`);
}

bootstrap();
