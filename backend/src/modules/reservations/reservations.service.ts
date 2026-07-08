import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateReservationDto } from './dto/create-reservation.dto';
import { UpdateReservationDto } from './dto/update-reservation.dto';
import { UpdateReservationStatusDto } from './dto/update-reservation-status.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';
import { resolveBranchScope } from '../../common/utils/branch-scope.util';
import { buildPaginationMeta } from '../../common/dto/pagination.dto';
import { BranchFilterDto } from '../../common/dto/branch-filter.dto';

@Injectable()
export class ReservationsService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(currentUser: CurrentUserPayload, filter: BranchFilterDto) {
    const branchId = resolveBranchScope(currentUser, filter.branchId);
    const where = branchId ? { branchId } : {};

    const [items, total] = await Promise.all([
      this.prisma.reservation.findMany({
        where,
        orderBy: { reservationTime: 'asc' },
        skip: filter.skip,
        take: filter.take,
      }),
      this.prisma.reservation.count({ where }),
    ]);

    return { data: items, meta: buildPaginationMeta(total, filter.page ?? 1, filter.take) };
  }

  async findOne(id: string) {
    const reservation = await this.prisma.reservation.findUnique({ where: { id } });
    if (!reservation) throw new NotFoundException('Reservation not found');
    return reservation;
  }

  create(dto: CreateReservationDto) {
    return this.prisma.reservation.create({
      data: { ...dto, reservationTime: new Date(dto.reservationTime) },
    });
  }

  async update(id: string, dto: UpdateReservationDto) {
    await this.findOne(id);
    return this.prisma.reservation.update({
      where: { id },
      data: { ...dto, reservationTime: dto.reservationTime ? new Date(dto.reservationTime) : undefined },
    });
  }

  async updateStatus(id: string, dto: UpdateReservationStatusDto) {
    await this.findOne(id);
    return this.prisma.reservation.update({ where: { id }, data: { status: dto.status } });
  }
}
