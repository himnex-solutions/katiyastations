// ============================================================
// KATIYA STATION RMS — DATABASE SEED
// Creates: initial super admin, a default branch, and a small
// demo menu so the Flutter app has something to talk to on a
// fresh VPS deployment.
// Run with: npm run prisma:seed
// ============================================================

import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';

const prisma = new PrismaClient();

async function main() {
  const branch = await prisma.branch.upsert({
    where: { id: 'a0000000-0000-4000-8000-000000000001' },
    update: {},
    create: {
      id: 'a0000000-0000-4000-8000-000000000001',
      name: 'Katiya Station — Main Branch',
      city: 'Kathmandu',
      vatRate: 13.0,
      serviceChargeRate: 10.0,
    },
  });

  const superAdminEmail = process.env.SEED_SUPER_ADMIN_EMAIL ?? 'admin@katiyastation.com';
  const superAdminPassword = process.env.SEED_SUPER_ADMIN_PASSWORD ?? 'ChangeMe123!';

  const passwordHash = await argon2.hash(superAdminPassword);
  await prisma.user.upsert({
    where: { email: superAdminEmail },
    update: {},
    create: {
      email: superAdminEmail,
      passwordHash,
      fullName: 'System Administrator',
      role: 'super_admin',
      isActive: true,
    },
  });

  const branchManagerPasswordHash = await argon2.hash('ChangeMe123!');
  await prisma.user.upsert({
    where: { email: 'manager@katiyastation.com' },
    update: {},
    create: {
      email: 'manager@katiyastation.com',
      passwordHash: branchManagerPasswordHash,
      fullName: 'Branch Manager',
      role: 'branch_manager',
      branchId: branch.id,
      isActive: true,
    },
  });

  const foodCategory = await prisma.menuCategory.upsert({
    where: { branchId_name: { branchId: branch.id, name: 'Main Course' } },
    update: {},
    create: { branchId: branch.id, name: 'Main Course', type: 'food', sortOrder: 1 },
  });

  const drinksCategory = await prisma.menuCategory.upsert({
    where: { branchId_name: { branchId: branch.id, name: 'Beverages' } },
    update: {},
    create: { branchId: branch.id, name: 'Beverages', type: 'drink', sortOrder: 2 },
  });

  const demoItems = [
    { name: 'Chicken Momo', price: 220, categoryId: foodCategory.id, type: 'food' },
    { name: 'Veg Thukpa', price: 180, categoryId: foodCategory.id, type: 'food' },
    { name: 'Chicken Sekuwa', price: 350, categoryId: foodCategory.id, type: 'food' },
    { name: 'Masala Tea', price: 60, categoryId: drinksCategory.id, type: 'drink' },
    { name: 'Fresh Lime Soda', price: 90, categoryId: drinksCategory.id, type: 'drink' },
  ];

  for (const item of demoItems) {
    const existing = await prisma.menuItem.findFirst({
      where: { branchId: branch.id, name: item.name },
    });
    if (!existing) {
      await prisma.menuItem.create({
        data: {
          branchId: branch.id,
          categoryId: item.categoryId,
          name: item.name,
          price: item.price,
          type: item.type,
        },
      });
    }
  }

  const tableNumbers = ['T1', 'T2', 'T3', 'T4', 'T5'];
  for (const tableNumber of tableNumbers) {
    await prisma.restaurantTable.upsert({
      where: { branchId_tableNumber: { branchId: branch.id, tableNumber } },
      update: {},
      create: { branchId: branch.id, tableNumber, capacity: 4 },
    });
  }
  // eslint-disable-next-line no-console
  console.log('Seed complete.');
  // eslint-disable-next-line no-console
  console.log(`Super admin login: ${superAdminEmail} / ${superAdminPassword}`);
}
main()
  .catch((error) => {
    // eslint-disable-next-line no-console
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
