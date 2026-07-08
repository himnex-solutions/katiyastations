import { Controller, Get, Query } from '@nestjs/common';
import { ReportsService } from './reports.service';
import { ReportFilterDto } from './dto/report-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { BlockSuperAdmin } from '../../common/decorators/block-super-admin.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@BlockSuperAdmin()
@Roles('branch_manager', 'accountant')
@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  // Cashiers may pull their own sales/collection summary for export; the
  // service withholds expense/purchase/profit figures from them. This
  // method-level @Roles overrides the manager/accountant class default.
  @Roles('branch_manager', 'accountant', 'cashier')
  @Get('summary')
  summary(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.summary(user, filter);
  }

  @Get('dashboard')
  dashboard(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.dashboard(user, filter);
  }

  @Get('sales')
  sales(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.sales(user, filter);
  }

  @Get('inventory')
  inventory(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.inventory(user, filter);
  }

  @Get('staff')
  staff(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.staff(user, filter);
  }

  @Get('revenue')
  revenue(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.revenue(user, filter);
  }

  @Get('popular-items')
  popularItems(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.popularItems(user, filter);
  }

  @Get('void-items')
  voidItems(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.voidItems(user, filter);
  }

  @Get('discounts')
  discounts(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.discounts(user, filter);
  }

  @Get('peak-hours')
  peakHours(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.peakHours(user, filter);
  }

  @Get('table-turnover')
  tableTurnover(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.tableTurnover(user, filter);
  }

  @Get('waiter-performance')
  waiterPerformance(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.waiterPerformance(user, filter);
  }

  @Get('kitchen-performance')
  kitchenPerformance(@CurrentUser() user: CurrentUserPayload, @Query() filter: ReportFilterDto) {
    return this.reportsService.kitchenPerformance(user, filter);
  }
}
