export interface AccessTokenPayload {
  sub: string; // userId
  email: string;
  role: string;
  branchId: string | null;
}

export interface RefreshTokenPayload {
  sub: string; // userId
  jti: string; // refresh_tokens.id — used for revocation lookup
}
