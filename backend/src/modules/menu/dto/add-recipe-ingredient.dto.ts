import { IsNumber, IsUUID, Min } from 'class-validator';

export class AddRecipeIngredientDto {
  @IsUUID()
  inventoryItemId: string;

  @IsNumber()
  @Min(0.0001)
  quantity: number;
}
