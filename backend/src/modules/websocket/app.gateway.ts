import { Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { AccessTokenPayload } from '../auth/interfaces/jwt-payload.interface';

/** Event names — must match lib/core/network/socket_client.dart SocketEvents. */
export const SocketEvents = {
  kotNew: 'kot:new',
  kotUpdated: 'kot:updated',
  kotStatusChanged: 'kot:status_changed',
  tableStatusChanged: 'table:status_changed',
  sessionOpened: 'session:opened',
  sessionClosed: 'session:closed',
  orderItemAdded: 'order:item_added',
  orderItemCancelled: 'order:item_cancelled',
  billGenerated: 'bill:generated',
  billPaid: 'bill:paid',
  inventoryLowStock: 'inventory:low_stock',
  notificationNew: 'notification:new',
  shiftClosed: 'shift:closed',
  shiftApproved: 'shift:approved',
  tableTransferred: 'table:transferred',
  waiterAssigned: 'session:waiter_assigned',
  userChanged: 'user:changed',
  purchaseCreated: 'purchase:created',
  menuChanged: 'menu:changed',
  dataChanged: 'data:changed',
} as const;

export const SocketRooms = {
  branch: (branchId: string) => `branch:${branchId}`,
  table: (tableId: string) => `table:${tableId}`,
  kitchen: (branchId: string) => `kitchen:${branchId}`,
  /** Everyone in `branchId` holding `role` — how a notification finds its audience. */
  role: (branchId: string, role: string) => `branch:${branchId}:role:${role}`,
};

@WebSocketGateway({
  namespace: '/rms',
  cors: { origin: '*' },
})
export class AppGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(AppGateway.name);

  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async handleConnection(client: Socket) {
    try {
      const token = client.handshake.auth?.token as string | undefined;
      if (!token) throw new UnauthorizedException();

      const payload = await this.jwtService.verifyAsync<AccessTokenPayload>(token, {
        secret: this.configService.get<string>('jwt.accessSecret'),
      });

      client.data.user = payload;

      // Joined from the verified token, never from a client-supplied room
      // name: a waiter must not be able to subscribe to the manager's alerts
      // by emitting `join_room` with someone else's role.
      if (payload.branchId) {
        void client.join(SocketRooms.role(payload.branchId, payload.role));
      }

      this.logger.log(`Client connected: ${client.id} (user ${payload.sub})`);
    } catch {
      this.logger.warn(`Rejected unauthenticated socket connection: ${client.id}`);
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`Client disconnected: ${client.id}`);
  }

  @SubscribeMessage('join_room')
  handleJoinRoom(@ConnectedSocket() client: Socket, @MessageBody() room: string) {
    client.join(room);
  }

  @SubscribeMessage('leave_room')
  handleLeaveRoom(@ConnectedSocket() client: Socket, @MessageBody() room: string) {
    client.leave(room);
  }

  /** Broadcast helper for other modules — see RealtimeService. */
  emitToRoom(room: string, event: string, payload: unknown) {
    this.server.to(room).emit(event, payload);
  }

  /**
   * Delivers one event to sockets in any of [rooms] — **once each**, even for a
   * socket that belongs to several of them.
   *
   * Calling emitToRoom() once per room does not do this: each call is its own
   * broadcast, so a client in both `kitchen:<b>` and `branch:<b>` (which is
   * every client — see socket_client.dart joinBranchRoom) received the same
   * `kot:new` twice and auto-printed the ticket twice. Socket.IO de-duplicates
   * recipients within a single `.to([...])` emit, so this cannot.
   */
  emitToRooms(rooms: string[], event: string, payload: unknown) {
    this.server.to(rooms).emit(event, payload);
  }
}
