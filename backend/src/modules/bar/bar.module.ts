import { Module } from '@nestjs/common';
import { BarController } from './bar.controller';
import { BarService } from './bar.service';
import { WebsocketModule } from '../websocket/websocket.module';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [WebsocketModule, NotificationsModule],
  controllers: [BarController],
  providers: [BarService],
  exports: [BarService],
})
export class BarModule {}
