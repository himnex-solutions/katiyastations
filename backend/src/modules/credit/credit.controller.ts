import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { CreditService } from './credit.service';
import { CreateCreditDto } from './dto/create-credit.dto';
import { SettleCreditDto } from './dto/settle-credit.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { BlockSuperAdmin } from '../../common/decorators/block-super-admin.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@BlockSuperAdmin()
@Roles('branch_manager', 'cashier', 'accountant')
@Controller('credit')
export class CreditController {
  constructor(private readonly creditService: CreditService) {}

  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.creditService.findAll(user, filter);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.creditService.findOne(id);
  }

  @Post()
  create(@Body() dto: CreateCreditDto) {
    return this.creditService.create(dto);
  }

  @Post(':id/settle')
  settle(@Param('id') id: string, @Body() dto: SettleCreditDto) {
    return this.creditService.settle(id, dto);
  }
}
