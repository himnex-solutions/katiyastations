import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { UsersService } from './users.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser, CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Roles('super_admin', 'branch_manager')
  @Get()
  findAll(@CurrentUser() user: CurrentUserPayload, @Query() filter: BranchFilterDto) {
    return this.usersService.findAll(user, filter);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.usersService.findOne(id);
  }

  @Roles('super_admin', 'branch_manager')
  @Post()
  create(@CurrentUser() user: CurrentUserPayload, @Body() dto: CreateUserDto) {
    return this.usersService.create(user, dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Patch(':id')
  update(@Param('id') id: string, @CurrentUser() user: CurrentUserPayload, @Body() dto: UpdateUserDto) {
    return this.usersService.update(id, user, dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Patch(':id/toggle-active')
  toggleActive(@Param('id') id: string, @CurrentUser() user: CurrentUserPayload) {
    return this.usersService.toggleActive(id, user);
  }

  @Roles('super_admin', 'branch_manager')
  @Patch(':id/reset-password')
  resetPassword(
    @Param('id') id: string,
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: ResetPasswordDto,
  ) {
    return this.usersService.resetPassword(id, user, dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Delete(':id')
  remove(@Param('id') id: string, @CurrentUser() user: CurrentUserPayload) {
    return this.usersService.remove(id, user);
  }
}
