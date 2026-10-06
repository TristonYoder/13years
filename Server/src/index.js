// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import { createServer } from 'node:http';
import { WebSocketServer } from 'ws';
import { resolveOrgIdForToken } from './auth.js';
import { joinRoom, relay, roomSize, roomCount } from './rooms.js';

const PORT = Number(process.env.PORT || 8080);
const HEARTBEAT_INTERVAL_MS = 30_000;

const httpServer = createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', rooms: roomCount() }));
    return;
  }
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not found. This server only speaks WebSocket on /relay.');
});

const wss = new WebSocketServer({ noServer: true });

httpServer.on('upgrade', async (req, socket, head) => {
  if (req.url !== '/relay') {
    socket.destroy();
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
    console.error('[relay] auth check failed:', err);
    rejectUpgrade(socket, 502, 'Auth check failed');
    return;
  }

  if (!orgId) {
    rejectUpgrade(socket, 401, 'Invalid or expired token');
    return;
  }

  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req, orgId);
  });
});

wss.on('connection', (ws, req, orgId) => {
  const leave = joinRoom(orgId, ws);
  ws.isAlive = true;
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
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_INTERVAL_MS);

wss.on('close', () => clearInterval(heartbeat));

function bearerToken(req) {
  const header = req.headers['authorization'];
  if (!header || !header.startsWith('Bearer ')) return undefined;
  return header.slice('Bearer '.length).trim();
}

function rejectUpgrade(socket, statusCode, message) {
  const statusText = { 401: 'Unauthorized', 502: 'Bad Gateway' }[statusCode] || 'Error';
  socket.write(
    `HTTP/1.1 ${statusCode} ${statusText}\r\n` +
      'Content-Type: text/plain\r\n' +
      'Connection: close\r\n\r\n' +
      message
  );
  socket.destroy();
}

httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`[relay] listening on :${PORT}`);
});
