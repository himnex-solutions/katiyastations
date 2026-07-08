import { IsIn, IsOptional, IsString } from 'class-validator';

export const DEVICE_PLATFORM_VALUES = ['android', 'ios', 'windows', 'web'] as const;

export class RegisterDeviceTokenDto {
  @IsString()
  token: string;

  @IsOptional()
  @IsIn(DEVICE_PLATFORM_VALUES)
  platform?: (typeof DEVICE_PLATFORM_VALUES)[number];
}
