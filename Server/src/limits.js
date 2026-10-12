// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

export const MAX_PAYLOAD_BYTES = 1024 * 1024;
export const REVALIDATE_INTERVAL_MS = 10 * 60 * 1000;
export const UPGRADES_PER_WINDOW = 20;
export const UPGRADE_WINDOW_MS = 10_000;

export function createRateLimiter({ limit = UPGRADES_PER_WINDOW, windowMs = UPGRADE_WINDOW_MS, now = Date.now } = {}) {
  const hits = new Map();

  function allow(key) {
    const current = now();
    const recent = (hits.get(key) ?? []).filter((time) => current - time < windowMs);
    if (recent.length >= limit) {
      hits.set(key, recent);
      return false;
    }
    recent.push(current);
    hits.set(key, recent);
    return true;
  }

  function sweep() {
    const current = now();
    for (const [key, times] of hits) {
      if (times.every((time) => current - time >= windowMs)) hits.delete(key);
    }
  }

  return { allow, sweep, size: () => hits.size };
}

export function clientAddress(req, trustProxy = false) {
  if (trustProxy) {
    const forwarded = req.headers['x-forwarded-for'];
    if (typeof forwarded === 'string' && forwarded.length > 0) {
      return forwarded.split(',')[0].trim();
    }
  }
  return req.socket?.remoteAddress ?? 'unknown';
}

export async function revalidateConnections(connections, revalidate, close = (ws) => ws.close(4001, 'Token revoked')) {
  const byToken = new Map();
  for (const ws of connections) {
    if (!ws.token) continue;
    if (!byToken.has(ws.token)) byToken.set(ws.token, []);
    byToken.get(ws.token).push(ws);
  }

  let closed = 0;
  for (const [token, sockets] of byToken) {
    let orgId;
    try {
      orgId = await revalidate(token);
    } catch {
      continue;
    }
    for (const ws of sockets) {
      if (orgId && (!ws.orgId || ws.orgId === orgId)) continue;
      close(ws);
      closed++;
    }
  }
  return closed;
}
