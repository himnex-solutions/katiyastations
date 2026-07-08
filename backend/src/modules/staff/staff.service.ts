import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateStaffDto } from './dto/create-staff.dto';
import { UpdateStaffDto } from './dto/update-staff.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

@Injectable()
export class StaffService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = {
      ...(branchId ? { branchId } : {}),
      ...(filter.search ? { name: { contains: filter.search, mode: 'insensitive' as const } } : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.staffMember.findMany({ where, orderBy: { name: 'asc' }, skip: filter.skip, take: filter.take }),
      this.prisma.staffMember.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const staff = await this.prisma.staffMember.findUnique({ where: { id } });
    if (!staff) throw new NotFoundException('Staff member not found');
    return staff;
  }

  /** Used for self-service attendance: resolves the caller's own StaffMember record. */
  async findByUserId(userId: string) {
    const staff = await this.prisma.staffMember.findUnique({ where: { userId } });
    if (!staff) throw new NotFoundException('No staff record is linked to your account');
    return staff;
  }

  create(dto: CreateStaffDto) {
    return this.prisma.staffMember.create({ data: dto });
  }

  async update(id: string, dto: UpdateStaffDto) {
    await this.findOne(id);
    return this.prisma.staffMember.update({ where: { id }, data: dto });
  }
}
