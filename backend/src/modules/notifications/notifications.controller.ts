import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { CreateNotificationDto } from './dto/create-notification.dto';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.notificationsService.findAll(user, filter);
  }

  @Post()
  create(@Body() dto: CreateNotificationDto) {
    return this.notificationsService.create(dto);
  }

  @Patch(':id/read')
  markRead(@Param('id') id: string) {
    return this.notificationsService.markRead(id);
  }

  @Patch('mark-all-read')
  markAllRead(@CurrentUser() user: CurrentUserPayload, @Query('branchId') branchId?: string) {
    return this.notificationsService.markAllRead(user, branchId);
  }

  @Post('fcm-token')
  registerDeviceToken(@CurrentUser() user: CurrentUserPayload, @Body() dto: RegisterDeviceTokenDto) {
    return this.notificationsService.registerDeviceToken(user.userId, dto);
  }
}
