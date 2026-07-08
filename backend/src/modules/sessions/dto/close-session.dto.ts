// Sessions always close to 'closed' — 'billed' is set exclusively by
// BillingService.generate() alongside a real Bill record, never here.
export class CloseSessionDto {}
