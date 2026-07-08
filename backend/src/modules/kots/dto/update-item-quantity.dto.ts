import { IsInt } from 'class-validator';

export class UpdateItemQuantityDto {
  /** New quantity; <= 0 cancels the item instead of deleting it. */
  @IsInt()
  quantity: number;
}
