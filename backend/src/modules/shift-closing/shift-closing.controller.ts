import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ShiftClosingService } from './shift-closing.service';
import { CreateShiftClosingDto } from './dto/create-shift-closing.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { BlockSuperAdmin } from '../../common/decorators/block-super-admin.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@BlockSuperAdmin()
@Roles('branch_manager', 'cashier', 'accountant')
@Controller('shift-closing')
export class ShiftClosingController {
  constructor(private readonly shiftClosingService: ShiftClosingService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.shiftClosingService.findAll(user, filter);
  }

  @Get('today-summary')
  todaySummary(@CurrentUser() user: CurrentUserPayload, @Query('branchId') branchId?: string) {
    return this.shiftClosingService.todaySummary(user, branchId);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.shiftClosingService.findOne(id);
  }

  @Post()
  create(@CurrentUser() user: CurrentUserPayload, @Body() dto: CreateShiftClosingDto) {
    return this.shiftClosingService.create(user, dto);
  }

  @Roles('branch_manager', 'accountant')
  @Post(':id/approve')
  approve(@Param('id') id: string) {
    return this.shiftClosingService.approve(id);
  }

  @Roles('branch_manager', 'accountant')
  @Post(':id/reject')
  reject(@Param('id') id: string) {
    return this.shiftClosingService.reject(id);
  }
}
