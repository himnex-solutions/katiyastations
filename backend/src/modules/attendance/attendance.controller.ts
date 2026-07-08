import { Controller, Get, Param, Post } from '@nestjs/common';
import { AttendanceService } from './attendance.service';
import { Roles } from '../../common/decorators/roles.decorator';

const SELF_SERVICE_ROLES = [
  'super_admin',
  'branch_manager',
  'cashier',
  'waiter',
  'kitchen',
  'inventory',
  'accountant',
] as const;

@Controller('attendance')
export class AttendanceController {
  constructor(private readonly attendanceService: AttendanceService) {}

  @Roles('super_admin', 'branch_manager')
  @Get('staff/:staffId')
  byStaff(@Param('staffId') staffId: string) {
    return this.attendanceService.byStaff(staffId);
  }

  @Roles(...SELF_SERVICE_ROLES)
  @Get('staff/:staffId/today')
  today(@Param('staffId') staffId: string) {
    return this.attendanceService.today(staffId);
  }

  @Roles('super_admin', 'branch_manager')
  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.attendanceService.findOne(id);
  }

  @Roles(...SELF_SERVICE_ROLES)
  @Post(':staffId/clock-in')
  clockIn(@Param('staffId') staffId: string) {
    return this.attendanceService.clockIn(staffId);
  }

  @Roles(...SELF_SERVICE_ROLES)
  @Post(':staffId/clock-out')
  clockOut(@Param('staffId') staffId: string) {
    return this.attendanceService.clockOut(staffId);
  }
}
