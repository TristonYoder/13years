// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

const rooms = new Map();

export function joinRoom(orgId, socket) {
  let room = rooms.get(orgId);
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

export function relay(orgId, senderSocket, data, isBinary) {
  const room = rooms.get(orgId);
  if (!room) return 0;

  let delivered = 0;
  for (const socket of room) {
    if (socket === senderSocket) continue;
    if (socket.readyState !== socket.OPEN) continue;
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
