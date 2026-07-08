import { IsString, IsUUID } from 'class-validator';

export class CreateNotificationDto {
  @IsUUID()
  branchId: string;

  @IsString()
  title: string;

  @IsString()
  body: string;
}
