import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { SessionsService } from './sessions.service';
import { CloseSessionDto } from './dto/close-session.dto';
import { HoldSessionDto } from './dto/hold-session.dto';
import { MergeSessionDto } from './dto/merge-session.dto';
import { SplitSessionDto } from './dto/split-session.dto';
import { FindSessionsDto } from './dto/find-sessions.dto';
import { ReassignWaiterDto } from './dto/reassign-waiter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Roles('super_admin', 'branch_manager', 'cashier', 'waiter')
@Controller('sessions')
export class SessionsController {
  constructor(private readonly sessionsService: SessionsService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: FindSessionsDto) {
    return this.sessionsService.findAll(user, filter);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.sessionsService.findOne(id);
  }

  @Get(':id/kots')
  kots(@Param('id') id: string) {
    return this.sessionsService.kots(id);
  }

  @Post(':id/close')
  close(@Param('id') id: string, @Body() dto: CloseSessionDto, @CurrentUser() user: CurrentUserPayload) {
    return this.sessionsService.close(id, dto, user);
  }

  @Post(':id/hold')
  hold(@Param('id') id: string, @Body() dto: HoldSessionDto, @CurrentUser() user: CurrentUserPayload) {
    return this.sessionsService.hold(id, dto, user);
  }

  @Post(':id/unhold')
  unhold(@Param('id') id: string, @CurrentUser() user: CurrentUserPayload) {
    return this.sessionsService.unhold(id, user);
  }

  @Post(':id/merge')
  merge(@Param('id') id: string, @Body() dto: MergeSessionDto, @CurrentUser() user: CurrentUserPayload) {
    return this.sessionsService.merge(id, dto, user);
  }

  @Post(':id/split')
  split(
    @Param('id') id: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: SplitSessionDto,
  ) {
    return this.sessionsService.split(id, user, dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Patch(':id/waiter')
  reassignWaiter(
    @Param('id') id: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: ReassignWaiterDto,
  ) {
    return this.sessionsService.reassignWaiter(id, user, dto);
  }
}
