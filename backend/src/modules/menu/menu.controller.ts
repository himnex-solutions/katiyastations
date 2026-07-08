import {
  Body,
  Controller,
  Delete,
  Get,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { MenuService } from './menu.service';
import { CreateCategoryDto } from './dto/create-category.dto';
import { UpdateCategoryDto } from './dto/update-category.dto';
import { CreateMenuItemDto } from './dto/create-menu-item.dto';
import { UpdateMenuItemDto } from './dto/update-menu-item.dto';
import { UpdateRecipeDto } from './dto/update-recipe.dto';
import { AddRecipeIngredientDto } from './dto/add-recipe-ingredient.dto';
import { Roles } from '../../common/decorators/roles.decorator';

@Controller('menu')
export class MenuController {
  constructor(private readonly menuService: MenuService) {}

  // ── Categories ────────────────────────────────────────────

  @Get('categories')
  findCategories(@Query('branchId') branchId?: string) {
    return this.menuService.findCategories(branchId);
  }

  @Get('categories/:id')
  findCategory(@Param('id') id: string) {
    return this.menuService.findCategory(id);
  }

  @Roles('super_admin', 'branch_manager')
  @Post('categories')
  createCategory(@Body() dto: CreateCategoryDto) {
    return this.menuService.createCategory(dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Patch('categories/:id')
  updateCategory(@Param('id') id: string, @Body() dto: UpdateCategoryDto) {
    return this.menuService.updateCategory(id, dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Delete('categories/:id')
  removeCategory(@Param('id') id: string) {
    return this.menuService.removeCategory(id);
  }

  // ── Items ─────────────────────────────────────────────────

  @Get('items')
  findItems(@Query('branchId') branchId?: string, @Query('categoryId') categoryId?: string) {
    return this.menuService.findItems(branchId, categoryId);
  }

  @Get('items/:id')
  findItem(@Param('id') id: string) {
    return this.menuService.findItem(id);
  }

  @Roles('super_admin', 'branch_manager')
  @Post('items')
  createItem(@Body() dto: CreateMenuItemDto) {
    return this.menuService.createItem(dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Patch('items/:id')
  updateItem(@Param('id') id: string, @Body() dto: UpdateMenuItemDto) {
    return this.menuService.updateItem(id, dto);
  }

  @Roles('super_admin', 'branch_manager')
  @Delete('items/:id')
  removeItem(@Param('id') id: string) {
    return this.menuService.removeItem(id);
  }

  // ── Recipes ───────────────────────────────────────────────

  @Get('items/:id/recipe')
  getRecipe(@Param('id') id: string) {
    return this.menuService.getRecipe(id);
  }

  @Roles('super_admin', 'branch_manager', 'inventory')
  @Post('items/:id/recipe')
  createRecipe(@Param('id') id: string) {
    return this.menuService.createRecipe(id);
  }

  @Roles('super_admin', 'branch_manager', 'inventory')
  @Patch('recipes/:id')
  updateRecipe(@Param('id') id: string, @Body() dto: UpdateRecipeDto) {
    return this.menuService.updateRecipe(id, dto);
  }

  @Roles('super_admin', 'branch_manager', 'inventory')
  @Post('recipes/:id/ingredients')
  addRecipeIngredient(@Param('id') id: string, @Body() dto: AddRecipeIngredientDto) {
    return this.menuService.addRecipeIngredient(id, dto);
  }

  @Roles('super_admin', 'branch_manager', 'inventory')
  @Delete('recipe-ingredients/:id')
  removeRecipeIngredient(@Param('id') id: string) {
    return this.menuService.removeRecipeIngredient(id);
  }

  // ── Bulk / branch ─────────────────────────────────────────

  @Get('branch/:branchId')
  findByBranch(@Param('branchId') branchId: string) {
    return this.menuService.findByBranch(branchId);
  }

  @Roles('super_admin', 'branch_manager')
  @Post('import/excel')
  @UseInterceptors(FileInterceptor('file'))
  importExcel(@UploadedFile() file: Express.Multer.File, @Query('branchId') branchId: string) {
    if (!file) throw new NotFoundException('No file uploaded');
    if (!branchId) throw new NotFoundException('branchId query parameter is required');
    return this.menuService.importExcel(branchId, file.buffer);
  }
}
