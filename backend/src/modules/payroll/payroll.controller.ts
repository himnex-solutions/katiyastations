import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { PayrollService } from './payroll.service';
import { GenerateSalaryDto } from './dto/generate-salary.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { BlockSuperAdmin } from '../../common/decorators/block-super-admin.decorator';

@BlockSuperAdmin()
@Roles('branch_manager', 'accountant')
@Controller('payroll')
export class PayrollController {
  constructor(private readonly payrollService: PayrollService) {}

  @Get()
  findAll(@Query('staffId') staffId?: string) {
    return this.payrollService.findAll(staffId);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.payrollService.findOne(id);
  }

  @Post(':staffId/generate')
  generate(@Param('staffId') staffId: string, @Body() dto: GenerateSalaryDto) {
    return this.payrollService.generate(staffId, dto);
  }
}
