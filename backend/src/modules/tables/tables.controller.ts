import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { TablesService } from './tables.service';
import { CreateTableDto } from './dto/create-table.dto';
import { UpdateTableDto } from './dto/update-table.dto';
import { OpenSessionDto } from './dto/open-session.dto';
import { TransferSessionDto } from './dto/transfer-session.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Controller('tables')
export class TablesController {
  constructor(private readonly tablesService: TablesService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query('branchId') branchId?: string) {
    return this.tablesService.findAll(user, branchId);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.tablesService.findOne(id);
  }

  @Get(':id/sessions')
  sessions(@Param('id') id: string) {
    return this.tablesService.sessions(id);
  }

  @Get(':id/current-session')
  currentSession(@Param('id') id: string) {
    return this.tablesService.currentSession(id);
  }

  @Roles('super_admin', 'branch_manager')
  @Post()
  create(@Body() dto: CreateTableDto) {
    return this.tablesService.create(dto);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter')
  @Post(':id/open')
  openSession(
    @Param('id') id: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: OpenSessionDto,
  ) {
    return this.tablesService.openSession(id, user, dto);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter', 'kitchen')
  @Patch(':id')
  update(@Param('id') id: string, @Body() dto: UpdateTableDto) {
    return this.tablesService.update(id, dto);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter')
  @Post(':id/request-bill')
  requestBill(@Param('id') id: string) {
    return this.tablesService.requestBill(id);
  }

  @Roles('super_admin', 'branch_manager', 'cashier', 'waiter')
  @Post(':id/transfer-session')
  transferSession(
    @Param('id') id: string,
    @Body() dto: TransferSessionDto,
    @CurrentUser() user: CurrentUserPayload,
  ) {
    return this.tablesService.transferSession(id, dto, user);
  }

  @Roles('super_admin', 'branch_manager')
  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.tablesService.remove(id);
  }
}
