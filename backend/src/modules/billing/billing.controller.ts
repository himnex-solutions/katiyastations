import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { BillingService } from './billing.service';
import { GenerateBillDto } from './dto/generate-bill.dto';
import { UpdateBillDto } from './dto/update-bill.dto';
import { AddPaymentDto } from './dto/add-payment.dto';
import { RefundBillDto } from './dto/refund-bill.dto';
import { PaymentPurgeRangeDto, PurgePaymentsDto } from './dto/purge-payments.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { BlockSuperAdmin } from '../../common/decorators/block-super-admin.decorator';
import { AllowSuperAdmin } from '../../common/decorators/allow-super-admin.decorator';
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

  @Roles('branch_manager', 'accountant', 'cashier')
  @Post('bills/:id/refund')
  refund(
    @Param('id') id: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: RefundBillDto,
  ) {
    return this.billingService.refund(id, user, dto);
  }

  @Get('payment-history')
  paymentHistory(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.billingService.paymentHistory(user, filter);
  }

  // ── Purging payment records ──────────────────────────────────
  //
  // The only two routes on this controller a super admin may call. The class is
  // @BlockSuperAdmin() because a system-operations account has no business
  // reading the restaurant's takings; these are opened deliberately so the same
  // account that already owns backup, restore and the fresh-start reset can
  // also clear a bad day's records without a manager having to be present.
  //
  // Both are scoped to one branch and one date window, and the delete needs the
  // word DELETE typed — see PurgePaymentsDto.

  @AllowSuperAdmin()
  @Roles('branch_manager', 'super_admin')
  @Get('payment-records/purge-preview')
  previewPaymentPurge(
    @CurrentUser() user: CurrentUserPayload,
    @Query() dto: PaymentPurgeRangeDto,
  ) {
    return this.billingService.previewPaymentPurge(user, dto);
  }

  @AllowSuperAdmin()
  @Roles('branch_manager', 'super_admin')
  @Delete('payment-records')
  purgePaymentRecords(
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: PurgePaymentsDto,
  ) {
    return this.billingService.purgePayments(user, dto);
  }
}
