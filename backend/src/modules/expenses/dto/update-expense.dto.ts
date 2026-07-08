import { PartialType, OmitType } from '@nestjs/swagger';
import { CreateExpenseDto } from './create-expense.dto';

export class UpdateExpenseDto extends PartialType(OmitType(CreateExpenseDto, ['branchId'] as const)) {}
