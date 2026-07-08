import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { LoyaltyService } from './loyalty.service';
import { EarnPointsDto } from './dto/earn-points.dto';
import { RedeemPointsDto } from './dto/redeem-points.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { BlockSuperAdmin } from '../../common/decorators/block-super-admin.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@BlockSuperAdmin()
@Roles('branch_manager', 'cashier', 'waiter')
@Controller('loyalty')
export class LoyaltyController {
  constructor(private readonly loyaltyService: LoyaltyService) {}

  @Get('recent')
  recentTransactions(@Query('branchId') branchId: string, @Query('limit') limit?: string) {
    return this.loyaltyService.recentTransactions(branchId, limit ? parseInt(limit, 10) : undefined);
  }

  @Get(':customerId/history')
  history(@Param('customerId') customerId: string) {
    return this.loyaltyService.history(customerId);
  }

  @Post(':customerId/earn')
  earn(
    @Param('customerId') customerId: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: EarnPointsDto,
  ) {
    return this.loyaltyService.earn(customerId, user, dto);
  }

  @Post(':customerId/redeem')
  redeem(
    @Param('customerId') customerId: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: RedeemPointsDto,
  ) {
    return this.loyaltyService.redeem(customerId, user, dto);
  }
}
