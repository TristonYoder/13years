// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

export const MAX_CONNECTIONS_PER_ORG = 64;
export const MAX_BUFFERED_BYTES = 2 * 1024 * 1024;

const rooms = new Map();

export function joinRoom(orgId, socket, maxConnections = MAX_CONNECTIONS_PER_ORG) {
  let room = rooms.get(orgId);
  if (room && room.size >= maxConnections) return null;
  if (!room) {
    room = new Set();
    rooms.set(orgId, room);
  }
  room.add(socket);

  return function leave() {
    const current = rooms.get(orgId);
    if (!current) return;
    current.delete(socket);
    if (current.size === 0) rooms.delete(orgId);
  };
}

export function isRoomFull(orgId, maxConnections = MAX_CONNECTIONS_PER_ORG) {
  return (rooms.get(orgId)?.size ?? 0) >= maxConnections;
}

export function relay(orgId, senderSocket, data, isBinary, maxBuffered = MAX_BUFFERED_BYTES) {
  const room = rooms.get(orgId);
  if (!room) return 0;

  let delivered = 0;
  for (const socket of [...room]) {
    if (socket === senderSocket) continue;
    if (socket.readyState !== socket.OPEN) continue;
    if ((socket.bufferedAmount ?? 0) > maxBuffered) {
      if (typeof socket.terminate === 'function') socket.terminate();
      continue;
    }
    socket.send(data, { binary: isBinary });
    delivered++;
  }
  return delivered;
}

export function roomSize(orgId) {
  return rooms.get(orgId)?.size ?? 0;
}

export function roomCount() {
  return rooms.size;
}
