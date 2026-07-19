import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
} from '@nestjs/common';
import { Request } from 'express';

/**
 * Brute-force protection for the login endpoint, keyed by **account email**
 * rather than by IP.
 *
 * Why per-account and not per-IP: a whole restaurant typically sits behind a
 * single public IP (shared WiFi), so an IP-based limit would treat every
 * staff member as one bucket and lock them all out at shift start. Keying on
 * the email means each staff account gets its own small budget — all 12 staff
 * can log in at once, while an attacker hammering a single account is stopped.
 *
 * State is in-memory (a single self-hosted instance), on a short rolling
 * window, so any accidental lockout clears itself within a minute and a
 * restart never leaves an account stuck.
 */
@Injectable()
export class LoginThrottleGuard implements CanActivate {
  private readonly limit = 5; // max attempts per account…
  private readonly windowMs = 60_000; // …within this rolling window (1 min)

  /** email -> recent attempt timestamps (ms) */
  private readonly attempts = new Map<string, number[]>();
  private lastPrune = Date.now();

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<Request>();
    const email = String((req.body as { email?: unknown })?.email ?? '')
      .trim()
      .toLowerCase();

    // No email → let the ValidationPipe reject it; nothing to rate-limit yet.
    if (!email) return true;

    const now = Date.now();
    this.pruneExpired(now);

    const recent = (this.attempts.get(email) ?? []).filter(
      (t) => now - t < this.windowMs,
    );

    if (recent.length >= this.limit) {
      throw new HttpException(
        'Too many login attempts for this account. Please wait a minute and try again.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    recent.push(now);
    this.attempts.set(email, recent);
    return true;
  }

  /**
   * Drop fully-expired accounts so a bot spraying many random emails cannot
   * grow the map without bound. Runs at most once per window.
   */
  private pruneExpired(now: number): void {
    if (now - this.lastPrune < this.windowMs) return;
    this.lastPrune = now;
    for (const [email, times] of this.attempts) {
      if (times.every((t) => now - t >= this.windowMs)) {
        this.attempts.delete(email);
      }
    }
  }
}
