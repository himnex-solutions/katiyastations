import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { BarService } from './bar.service';
import { CreateBarStockDto } from './dto/create-bar-stock.dto';
import { UpdateBarStockDto } from './dto/update-bar-stock.dto';
import { DispenseDto } from './dto/dispense.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Roles('super_admin', 'branch_manager', 'cashier', 'inventory')
@Controller('bar')
export class BarController {
  constructor(private readonly barService: BarService) {}

  @Get('stock')
  findAllStock(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.barService.findAllStock(user, filter);
  }

  @Get('stock/:id')
  findStock(@Param('id') id: string) {
    return this.barService.findStock(id);
  }

  @Post('stock')
  createStock(@Body() dto: CreateBarStockDto) {
    return this.barService.createStock(dto);
  }

  @Patch('stock/:id')
  updateStock(@Param('id') id: string, @Body() dto: UpdateBarStockDto) {
    return this.barService.updateStock(id, dto);
  }

  @Post('stock/:id/dispense')
  dispense(@Param('id') id: string, @Body() dto: DispenseDto) {
    return this.barService.dispense(id, dto);
  }

  @Delete('stock/:id')
  removeStock(@Param('id') id: string) {
    return this.barService.removeStock(id);
  }

  @Get('transactions')
  transactions(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.barService.transactions(user, filter);
  }
}
