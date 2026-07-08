import { SetMetadata } from '@nestjs/common';

export const RAW_RESPONSE_KEY = 'rawResponse';

/**
 * Opts a route out of the global SnakeCaseInterceptor. Use when the
 * handler already shapes its own response body exactly as the client
 * expects (e.g. auth token responses, which mix camelCase token fields
 * with a snake_case `user` object — see AuthService.login/refresh).
 */
export const RawResponse = () => SetMetadata(RAW_RESPONSE_KEY, true);
