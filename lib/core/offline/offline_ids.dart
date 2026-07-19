// ============================================================
// KATIYA STATION RMS — OFFLINE ID GENERATOR
// ============================================================

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A fresh v4 UUID used as the client-generated primary key for a record
/// created offline (a table session or a KOT).
///
/// The backend persists this exact id (the create endpoints accept a
/// client-supplied `id` and are idempotent on it), so an offline id becomes
/// the permanent server id — a KOT that references `sessionId = <this uuid>`
/// links up correctly once the session syncs, with no remapping needed.
String newOfflineId() => _uuid.v4();

/// Short, human-facing provisional number shown on an offline ticket until the
/// server assigns the real sequence number on sync (e.g. "OFF-3F9A").
String provisionalNumber(String id) =>
    'OFF-${id.replaceAll('-', '').substring(0, 4).toUpperCase()}';
