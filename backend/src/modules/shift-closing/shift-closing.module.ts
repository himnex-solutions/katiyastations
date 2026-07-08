import { Module } from '@nestjs/common';
import { ShiftClosingController } from './shift-closing.controller';
import { ShiftClosingService } from './shift-closing.service';
import { WebsocketModule } from '../websocket/websocket.module';

@Module({
  imports: [WebsocketModule],
  controllers: [ShiftClosingController],
  providers: [ShiftClosingService],
  exports: [ShiftClosingService],
})
export class ShiftClosingModule {}
