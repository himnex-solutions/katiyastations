import { Injectable } from '@nestjs/common';
import { AppGateway, SocketEvents, SocketRooms } from './app.gateway';

/**
 * Thin façade over AppGateway so feature modules (kots, billing, tables, ...)
 * can emit realtime events without importing Socket.IO types directly.
 */
@Injectable()
export class RealtimeService {
  constructor(private readonly gateway: AppGateway) {}

  kotNew(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.kitchen(branchId), SocketEvents.kotNew, payload);
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.kotNew, payload);
  }

  kotStatusChanged(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.kitchen(branchId), SocketEvents.kotStatusChanged, payload);
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.kotStatusChanged, payload);
  }

  tableStatusChanged(branchId: string, tableId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.tableStatusChanged, payload);
    this.gateway.emitToRoom(SocketRooms.table(tableId), SocketEvents.tableStatusChanged, payload);
  }

  sessionOpened(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.sessionOpened, payload);
  }

  sessionClosed(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.sessionClosed, payload);
  }

  billGenerated(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.billGenerated, payload);
  }

  billPaid(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.billPaid, payload);
  }

  lowStock(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.inventoryLowStock, payload);
  }

  notification(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.notificationNew, payload);
  }

  shiftClosed(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.shiftClosed, payload);
  }

  shiftApproved(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.shiftApproved, payload);
  }

  orderItemCancelled(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.kitchen(branchId), SocketEvents.orderItemCancelled, payload);
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.orderItemCancelled, payload);
  }

  tableTransferred(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.tableTransferred, payload);
  }

  waiterAssigned(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.waiterAssigned, payload);
  }

  /** A branch user account was created, updated, blocked, or deleted. */
  userChanged(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.userChanged, payload);
  }

  /** A purchase was recorded — refresh purchase lists and the daily report. */
  purchaseCreated(branchId: string, payload: unknown) {
    this.gateway.emitToRoom(SocketRooms.branch(branchId), SocketEvents.purchaseCreated, payload);
  }
}
