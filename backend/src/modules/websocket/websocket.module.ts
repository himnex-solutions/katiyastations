import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AppGateway } from './app.gateway';
import { RealtimeService } from './realtime.service';

@Module({
  imports: [JwtModule.register({})],
  providers: [AppGateway, RealtimeService],
  exports: [RealtimeService],
})
export class WebsocketModule {}
