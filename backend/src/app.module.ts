import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';

import appConfig from './config/app.config';
import databaseConfig from './config/database.config';
import redisConfig from './config/redis.config';
import jwtConfig from './config/jwt.config';
import minioConfig from './config/minio.config';

import { PrismaModule } from './prisma/prisma.module';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { BlockSuperAdminGuard } from './common/guards/block-super-admin.guard';
import { LoggingInterceptor } from './common/interceptors/logging.interceptor';
import { SnakeCaseInterceptor } from './common/interceptors/snake-case.interceptor';

import { AuthModule } from './modules/auth/auth.module';
import { BranchesModule } from './modules/branches/branches.module';
import { UsersModule } from './modules/users/users.module';
import { TablesModule } from './modules/tables/tables.module';
import { SessionsModule } from './modules/sessions/sessions.module';
import { KotsModule } from './modules/kots/kots.module';
import { MenuModule } from './modules/menu/menu.module';
import { BillingModule } from './modules/billing/billing.module';
import { CreditModule } from './modules/credit/credit.module';
import { InventoryModule } from './modules/inventory/inventory.module';
import { BarModule } from './modules/bar/bar.module';
import { SuppliersModule } from './modules/suppliers/suppliers.module';
import { PurchasesModule } from './modules/purchases/purchases.module';
import { ExpensesModule } from './modules/expenses/expenses.module';
import { CustomersModule } from './modules/customers/customers.module';
import { ReservationsModule } from './modules/reservations/reservations.module';
import { LoyaltyModule } from './modules/loyalty/loyalty.module';
import { StaffModule } from './modules/staff/staff.module';
import { AttendanceModule } from './modules/attendance/attendance.module';
import { PayrollModule } from './modules/payroll/payroll.module';
import { ShiftClosingModule } from './modules/shift-closing/shift-closing.module';
import { ReportsModule } from './modules/reports/reports.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { AuditLogsModule } from './modules/audit-logs/audit-logs.module';
import { WebsocketModule } from './modules/websocket/websocket.module';
import { UploadsModule } from './modules/uploads/uploads.module';
import { SuperAdminModule } from './modules/super-admin/super-admin.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [appConfig, databaseConfig, redisConfig, jwtConfig, minioConfig],
    }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    PrismaModule,

    AuthModule,
    BranchesModule,
    UsersModule,
    TablesModule,
    SessionsModule,
    KotsModule,
    MenuModule,
    BillingModule,
    CreditModule,
    InventoryModule,
    BarModule,
    SuppliersModule,
    PurchasesModule,
    ExpensesModule,
    CustomersModule,
    ReservationsModule,
    LoyaltyModule,
    StaffModule,
    AttendanceModule,
    PayrollModule,
    ShiftClosingModule,
    ReportsModule,
    NotificationsModule,
    AuditLogsModule,
    WebsocketModule,
    UploadsModule,
    SuperAdminModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_GUARD, useClass: BlockSuperAdminGuard },
    { provide: APP_INTERCEPTOR, useClass: LoggingInterceptor },
    { provide: APP_INTERCEPTOR, useClass: SnakeCaseInterceptor },
  ],
})
export class AppModule {}
