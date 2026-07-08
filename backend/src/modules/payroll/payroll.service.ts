import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { GenerateSalaryDto } from './dto/generate-salary.dto';

@Injectable()
export class PayrollService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(staffId?: string) {
    return this.prisma.salary.findMany({
      where: staffId ? { staffId } : {},
      orderBy: { paidAt: 'desc' },
    });
  }

  async findOne(id: string) {
    const salary = await this.prisma.salary.findUnique({ where: { id } });
    if (!salary) throw new NotFoundException('Salary record not found');
    return salary;
  }

  async generate(staffId: string, dto: GenerateSalaryDto) {
    const staff = await this.prisma.staffMember.findUnique({ where: { id: staffId } });
    if (!staff) throw new NotFoundException('Staff member not found');

    return this.prisma.salary.create({
      data: {
        staffId,
        amount: dto.amount ?? staff.salary,
      },
    });
  }
}
