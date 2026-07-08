import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { EarnPointsDto } from './dto/earn-points.dto';
import { RedeemPointsDto } from './dto/redeem-points.dto';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Injectable()
export class LoyaltyService {
  constructor(private readonly prisma: PrismaService) {}

  private async findCustomer(customerId: string) {
    const customer = await this.prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer) throw new NotFoundException('Customer not found');
    return customer;
  }

  async history(customerId: string) {
    await this.findCustomer(customerId);
    return this.prisma.loyaltyTransaction.findMany({
      where: { customerId },
      orderBy: { createdAt: 'desc' },
    });
  }

  async recentTransactions(branchId: string, limit = 50) {
    return this.prisma.loyaltyTransaction.findMany({
      where: { branchId },
      include: { customer: { select: { name: true, phone: true } } },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
  }

  async earn(customerId: string, currentUser: CurrentUserPayload, dto: EarnPointsDto) {
    const customer = await this.findCustomer(customerId);

    const [, transaction] = await this.prisma.$transaction([
      this.prisma.customer.update({
        where: { id: customerId },
        data: { loyaltyPoints: { increment: dto.points } },
      }),
      this.prisma.loyaltyTransaction.create({
        data: {
          customerId,
          branchId: customer.branchId,
          type: 'earn',
          points: dto.points,
          purchaseAmount: dto.purchaseAmount ?? 0,
          notes: dto.notes,
          createdBy: currentUser.userId,
        },
      }),
    ]);

    return transaction;
  }

  async redeem(customerId: string, currentUser: CurrentUserPayload, dto: RedeemPointsDto) {
    const customer = await this.findCustomer(customerId);
    if (customer.loyaltyPoints < dto.points) {
      throw new BadRequestException('Customer does not have enough loyalty points');
    }

    const [, transaction] = await this.prisma.$transaction([
      this.prisma.customer.update({
        where: { id: customerId },
        data: { loyaltyPoints: { decrement: dto.points } },
      }),
      this.prisma.loyaltyTransaction.create({
        data: {
          customerId,
          branchId: customer.branchId,
          type: 'redeem',
          points: dto.points,
          notes: dto.notes,
          createdBy: currentUser.userId,
        },
      }),
    ]);

    return transaction;
  }
}
