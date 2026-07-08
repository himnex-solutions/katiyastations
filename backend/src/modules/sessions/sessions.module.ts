import { Module } from '@nestjs/common';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';
import { WebsocketModule } from '../websocket/websocket.module';
import { KotsModule } from '../kots/kots.module';
import { AuditLogsModule } from '../audit-logs/audit-logs.module';

@Module({
  imports: [WebsocketModule, KotsModule, AuditLogsModule],
  controllers: [SessionsController],
  providers: [SessionsService],
  exports: [SessionsService],
})
export class SessionsModule {}
