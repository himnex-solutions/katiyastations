import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

function startOfToday(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

@Injectable()
export class AttendanceService {
  constructor(private readonly prisma: PrismaService) {}

  async findOne(id: string) {
    const record = await this.prisma.attendance.findUnique({ where: { id } });
    if (!record) throw new NotFoundException('Attendance record not found');
    return record;
  }

  byStaff(staffId: string) {
    return this.prisma.attendance.findMany({ where: { staffId }, orderBy: { date: 'desc' } });
  }

  today(staffId: string) {
    return this.prisma.attendance.findUnique({
      where: { staffId_date: { staffId, date: startOfToday() } },
    });
  }

  async clockIn(staffId: string) {
    const staff = await this.prisma.staffMember.findUnique({ where: { id: staffId } });
    if (!staff) throw new NotFoundException('Staff member not found');

    const today = startOfToday();
    const existing = await this.prisma.attendance.findUnique({
      where: { staffId_date: { staffId, date: today } },
    });
    if (existing) throw new BadRequestException('Staff member has already clocked in today');

    return this.prisma.attendance.create({
      data: { staffId, date: today },
    });
  }

  async clockOut(staffId: string) {
    const today = startOfToday();
    const record = await this.prisma.attendance.findUnique({
      where: { staffId_date: { staffId, date: today } },
    });
    if (!record) throw new BadRequestException('Staff member has not clocked in today');
    if (record.clockOut) throw new BadRequestException('Staff member has already clocked out today');

    return this.prisma.attendance.update({
      where: { id: record.id },
      data: { clockOut: new Date() },
    });
  }
}
