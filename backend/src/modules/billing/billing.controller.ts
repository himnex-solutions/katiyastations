import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { BillingService } from './billing.service';
import { GenerateBillDto } from './dto/generate-bill.dto';
import { UpdateBillDto } from './dto/update-bill.dto';
import { AddPaymentDto } from './dto/add-payment.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { BlockSuperAdmin } from '../../common/decorators/block-super-admin.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@BlockSuperAdmin()
@Roles('branch_manager', 'cashier', 'accountant')
@Controller('billing')
export class BillingController {
  constructor(private readonly billingService: BillingService) {}

  @Get('bills')
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.billingService.findAll(user, filter);
  }

  @Get('bills/:id')
  findOne(@Param('id') id: string) {
    return this.billingService.findOne(id);
  }

  @Post('sessions/:sessionId/generate')
  generate(
    @Param('sessionId') sessionId: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: GenerateBillDto,
  ) {
    return this.billingService.generate(sessionId, user, dto);
  }

  @Patch('bills/:id')
  update(@Param('id') id: string, @Body() dto: UpdateBillDto) {
    return this.billingService.update(id, dto);
  }

  @Post('bills/:id/payments')
  addPayment(
    @Param('id') id: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: AddPaymentDto,
  ) {
    return this.billingService.addPayment(id, user, dto);
  }

  @Get('payment-history')
  paymentHistory(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.billingService.paymentHistory(user, filter);
  }
}
