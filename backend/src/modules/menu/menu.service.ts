import { Injectable, NotFoundException } from '@nestjs/common';
import * as ExcelJS from 'exceljs';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateCategoryDto } from './dto/create-category.dto';
import { UpdateCategoryDto } from './dto/update-category.dto';
import { CreateMenuItemDto } from './dto/create-menu-item.dto';
import { UpdateMenuItemDto } from './dto/update-menu-item.dto';
import { UpdateRecipeDto } from './dto/update-recipe.dto';
import { AddRecipeIngredientDto } from './dto/add-recipe-ingredient.dto';
import { RealtimeService } from '../websocket/realtime.service';

@Injectable()
export class MenuService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  // ── Categories ────────────────────────────────────────────

  findCategories(branchId?: string) {
    return this.prisma.menuCategory.findMany({
      where: branchId ? { branchId } : {},
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
  }

  async findCategory(id: string) {
    const category = await this.prisma.menuCategory.findUnique({ where: { id } });
    if (!category) throw new NotFoundException('Menu category not found');
    return category;
  }

  async createCategory(dto: CreateCategoryDto) {
    const category = await this.prisma.menuCategory.create({ data: dto });
    this.realtime.menuChanged(category.branchId, { action: 'category_created', id: category.id });
    return category;
  }

  async updateCategory(id: string, dto: UpdateCategoryDto) {
    await this.findCategory(id);
    const category = await this.prisma.menuCategory.update({ where: { id }, data: dto });
    this.realtime.menuChanged(category.branchId, { action: 'category_updated', id });
    return category;
  }

  async removeCategory(id: string) {
    const category = await this.findCategory(id);
    await this.prisma.menuCategory.delete({ where: { id } });
    this.realtime.menuChanged(category.branchId, { action: 'category_deleted', id });
    return { deleted: true };
  }

  // ── Items ─────────────────────────────────────────────────

  findItems(branchId?: string, categoryId?: string) {
    return this.prisma.menuItem.findMany({
      where: {
        ...(branchId ? { branchId } : {}),
        ...(categoryId ? { categoryId } : {}),
      },
      include: { category: true },
      orderBy: { name: 'asc' },
    });
  }

  async findItem(id: string) {
    const item = await this.prisma.menuItem.findUnique({ where: { id }, include: { category: true } });
    if (!item) throw new NotFoundException('Menu item not found');
    return item;
  }

  async createItem(dto: CreateMenuItemDto) {
    const item = await this.prisma.menuItem.create({ data: dto });
    this.realtime.menuChanged(item.branchId, {
      action: 'item_created',
      id: item.id,
      categoryId: item.categoryId,
    });
    return item;
  }

  async updateItem(id: string, dto: UpdateMenuItemDto) {
    await this.findItem(id);
    const item = await this.prisma.menuItem.update({ where: { id }, data: dto });
    this.realtime.menuChanged(item.branchId, {
      action: 'item_updated',
      id,
      categoryId: item.categoryId,
    });
    return item;
  }

  async removeItem(id: string) {
    const item = await this.findItem(id);
    await this.prisma.menuItem.delete({ where: { id } });
    this.realtime.menuChanged(item.branchId, {
      action: 'item_deleted',
      id,
      categoryId: item.categoryId,
    });
    return { deleted: true };
  }

  // ── Recipes ───────────────────────────────────────────────

  async getRecipe(menuItemId: string) {
    return this.prisma.recipe.findUnique({
      where: { menuItemId },
      include: { ingredients: { include: { inventoryItem: { select: { name: true, unit: true } } } } },
    });
  }

  async createRecipe(menuItemId: string) {
    const item = await this.findItem(menuItemId);
    const existing = await this.prisma.recipe.findUnique({ where: { menuItemId } });
    if (existing) return existing;
    return this.prisma.recipe.create({
      data: { menuItemId, branchId: item.branchId, instructions: '' },
    });
  }

  async updateRecipe(recipeId: string, dto: UpdateRecipeDto) {
    const recipe = await this.prisma.recipe.findUnique({ where: { id: recipeId } });
    if (!recipe) throw new NotFoundException('Recipe not found');
    return this.prisma.recipe.update({ where: { id: recipeId }, data: dto });
  }

  async addRecipeIngredient(recipeId: string, dto: AddRecipeIngredientDto) {
    const recipe = await this.prisma.recipe.findUnique({ where: { id: recipeId } });
    if (!recipe) throw new NotFoundException('Recipe not found');
    return this.prisma.recipeIngredient.create({
      data: { recipeId, inventoryItemId: dto.inventoryItemId, quantity: dto.quantity },
    });
  }

  async removeRecipeIngredient(ingredientId: string) {
    await this.prisma.recipeIngredient.delete({ where: { id: ingredientId } });
    return { deleted: true };
  }

  async findByBranch(branchId: string) {
    const [categories, items] = await Promise.all([
      this.prisma.menuCategory.findMany({ where: { branchId }, orderBy: { sortOrder: 'asc' } }),
      this.prisma.menuItem.findMany({ where: { branchId }, orderBy: { name: 'asc' } }),
    ]);
    return { categories, items };
  }

  /**
   * Bulk-imports menu items from an Excel workbook. Expected columns
   * (header row, any order): category, name, price, cost_price, tax_rate,
   * description, type. Categories are created on demand.
   */
  async importExcel(branchId: string, fileBuffer: Buffer) {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(fileBuffer as any);
    const sheet = workbook.worksheets[0];
    if (!sheet) throw new NotFoundException('Excel file has no worksheets');

    const header = (sheet.getRow(1).values as unknown[]).map((v) =>
      String(v ?? '').trim().toLowerCase(),
    );
    const colIndex = (name: string) => header.indexOf(name);

    const categoryCache = new Map<string, string>();
    let created = 0;
    let skipped = 0;

    for (let rowNumber = 2; rowNumber <= sheet.rowCount; rowNumber++) {
      const row = sheet.getRow(rowNumber);
      const name = String(row.getCell(colIndex('name')).value ?? '').trim();
      const price = Number(row.getCell(colIndex('price')).value ?? NaN);
      const categoryName = String(row.getCell(colIndex('category')).value ?? '').trim();

      if (!name || !categoryName || Number.isNaN(price)) {
        skipped++;
        continue;
      }

      let categoryId = categoryCache.get(categoryName.toLowerCase());
      if (!categoryId) {
        const category = await this.prisma.menuCategory.upsert({
          where: { branchId_name: { branchId, name: categoryName } },
          update: {},
          create: { branchId, name: categoryName },
        });
        categoryId = category.id;
        categoryCache.set(categoryName.toLowerCase(), categoryId);
      }

      const costPriceIdx = colIndex('cost_price');
      const taxRateIdx = colIndex('tax_rate');
      const descriptionIdx = colIndex('description');
      const typeIdx = colIndex('type');
      const imageUrlIdx = colIndex('image url') >= 0 ? colIndex('image url') : colIndex('image_url');

      await this.prisma.menuItem.create({
        data: {
          branchId,
          categoryId,
          name,
          price,
          costPrice: costPriceIdx >= 0 ? Number(row.getCell(costPriceIdx).value) || undefined : undefined,
          taxRate: taxRateIdx >= 0 ? Number(row.getCell(taxRateIdx).value) || undefined : undefined,
          description: descriptionIdx >= 0 ? String(row.getCell(descriptionIdx).value ?? '') || undefined : undefined,
          imageUrl: imageUrlIdx >= 0 ? String(row.getCell(imageUrlIdx).value ?? '') || undefined : undefined,
          type: typeIdx >= 0 ? String(row.getCell(typeIdx).value ?? 'food') || 'food' : 'food',
        },
      });
      created++;
    }

    if (created > 0) {
      this.realtime.menuChanged(branchId, { action: 'imported', created, skipped });
    }
    return { created, skipped };
  }
}
