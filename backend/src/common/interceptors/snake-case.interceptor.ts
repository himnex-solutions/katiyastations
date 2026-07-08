import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { toSnakeCase } from '../utils/case.util';
import { RAW_RESPONSE_KEY } from '../decorators/raw-response.decorator';

/**
 * Converts every outgoing response body from camelCase (Prisma/TS) to
 * snake_case, matching the wire format the Flutter client expects
 * (inherited from the original Supabase/PostgREST column names).
 * Routes marked with @RawResponse() are passed through unchanged.
 */
@Injectable()
export class SnakeCaseInterceptor implements NestInterceptor {
  constructor(private readonly reflector: Reflector) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const isRaw = this.reflector.getAllAndOverride<boolean>(RAW_RESPONSE_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isRaw) return next.handle();

    return next.handle().pipe(map((result) => toSnakeCase(result)));
  }
}
