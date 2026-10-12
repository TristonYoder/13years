// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import { createServer } from 'node:http';
import { WebSocketServer } from 'ws';
import { resolveOrgIdForToken, revalidateToken } from './auth.js';
import { joinRoom, relay, roomSize, roomCount, isRoomFull } from './rooms.js';
import {
  MAX_PAYLOAD_BYTES,
  REVALIDATE_INTERVAL_MS,
  clientAddress,
  createRateLimiter,
  revalidateConnections,
} from './limits.js';

const PORT = Number(process.env.PORT || 8080);
const HEARTBEAT_INTERVAL_MS = 30_000;
const TRUST_PROXY = process.env.TRUST_PROXY === '1';

const upgradeLimiter = createRateLimiter();

const httpServer = createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', rooms: roomCount() }));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found. This server only speaks WebSocket on /relay.');
});

const wss = new WebSocketServer({
  noServer: true,
  maxPayload: MAX_PAYLOAD_BYTES,
  perMessageDeflate: false,
});

httpServer.on('upgrade', async (req, socket, head) => {
  socket.on('error', (err) => {
    console.error('[relay] raw socket error:', err.code || err.message);
  });

  if (req.url !== '/relay') {
    socket.destroy();
    return;
  }

  if (!upgradeLimiter.allow(clientAddress(req, TRUST_PROXY))) {
    rejectUpgrade(socket, 429, 'Too many connection attempts');
    return;
  }

  const token = bearerToken(req);
  if (!token) {
    rejectUpgrade(socket, 401, 'Missing bearer token');
    return;
  }

  let orgId;
  try {
    orgId = await resolveOrgIdForToken(token);
  } catch (err) {
    console.error('[relay] auth check failed:', err.name || err.message);
    rejectUpgrade(socket, 502, 'Auth check failed');
    return;
  }

  if (!orgId) {
    rejectUpgrade(socket, 401, 'Invalid or expired token');
    return;
  }

  if (isRoomFull(orgId)) {
    rejectUpgrade(socket, 503, 'Too many connections for this organization');
    return;
  }

  if (socket.destroyed) return;

  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req, orgId, token);
  });
});

wss.on('connection', (ws, req, orgId, token) => {
  const leave = joinRoom(orgId, ws);
  if (!leave) {
    ws.close(1013, 'Too many connections');
    return;
  }
  ws.isAlive = true;
  ws.orgId = orgId;
  ws.token = token;
  console.log(`[relay] joined org ${orgId} (${roomSize(orgId)} connected)`);

  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('message', (data, isBinary) => {
    relay(orgId, ws, data, isBinary);
  });

  ws.on('close', () => {
    leave();
    console.log(`[relay] left org ${orgId} (${roomSize(orgId)} remaining)`);
  });

  ws.on('error', (err) => {
    console.error(`[relay] socket error in org ${orgId}:`, err.message);
  });
});

const heartbeat = setInterval(() => {
  upgradeLimiter.sweep();
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_INTERVAL_MS);

const revalidation = setInterval(() => {
  revalidateConnections(wss.clients, (token) => revalidateToken(token)).then(
    (closed) => {
      if (closed > 0) console.log(`[relay] closed ${closed} connection(s) with revoked tokens`);
    },
    (err) => console.error('[relay] revalidation failed:', err.message)
  );
}, REVALIDATE_INTERVAL_MS);

wss.on('close', () => {
  clearInterval(heartbeat);
  clearInterval(revalidation);
});

function bearerToken(req) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) return undefined;
  return header.slice('Bearer '.length).trim();
}

function rejectUpgrade(socket, statusCode, message) {
  const statusText =
    { 401: 'Unauthorized', 429: 'Too Many Requests', 502: 'Bad Gateway', 503: 'Service Unavailable' }[statusCode] ||
    'Error';
  if (!socket.destroyed) {
    socket.write(
      `HTTP/1.1 ${statusCode} ${statusText}\r\n` +
        'Content-Type: text/plain\r\n' +
        'Connection: close\r\n\r\n' +
        message
    );
  }
  socket.destroy();
}

httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`[relay] listening on :${PORT}`);
});
