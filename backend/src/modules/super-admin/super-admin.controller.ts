import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { SuperAdminService } from './super-admin.service';
import { RestoreDto } from './dto/restore.dto';
import { Roles } from '../../common/decorators/roles.decorator';

@Roles('super_admin')
@Controller('super-admin')
export class SuperAdminController {
  constructor(private readonly superAdminService: SuperAdminService) {}

  @Get('health')
  health() {
    return this.superAdminService.health();
  }

  @Get('redis')
  redis() {
    return this.superAdminService.redisStatus();
  }

  @Get('database')
  database() {
    return this.superAdminService.databaseStatus();
  }

  @Get('containers')
  containers() {
    return this.superAdminService.containers();
  }

  @Get('logs')
  logs(@Query('lines') lines?: string) {
    return this.superAdminService.logs(lines ? parseInt(lines, 10) : undefined);
  }

  @Post('backup')
  backup() {
    return this.superAdminService.backup();
  }

  @Post('restore')
  restore(@Body() dto: RestoreDto) {
    return this.superAdminService.restore(dto.filename);
  }
}
