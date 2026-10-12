// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRateLimiter, clientAddress, revalidateConnections, MAX_PAYLOAD_BYTES } from './limits.js';

test('rate limiter allows the limit then refuses until the window passes', () => {
  let time = 0;
  const limiter = createRateLimiter({ limit: 3, windowMs: 1000, now: () => time });
  assert.equal(limiter.allow('1.1.1.1'), true);
  assert.equal(limiter.allow('1.1.1.1'), true);
  assert.equal(limiter.allow('1.1.1.1'), true);
  assert.equal(limiter.allow('1.1.1.1'), false);
  assert.equal(limiter.allow('2.2.2.2'), true);
  time = 1001;
  assert.equal(limiter.allow('1.1.1.1'), true);
  limiter.sweep();
});

test('client address honours forwarding only when trusted', () => {
  const req = { headers: { 'x-forwarded-for': '9.9.9.9, 10.0.0.1' }, socket: { remoteAddress: '10.0.0.1' } };
  assert.equal(clientAddress(req, false), '10.0.0.1');
  assert.equal(clientAddress(req, true), '9.9.9.9');
});

test('payload cap is 1 MiB', () => {
  assert.equal(MAX_PAYLOAD_BYTES, 1048576);
});

test('revalidation closes revoked tokens and keeps valid and unreachable ones', async () => {
  const sockets = [
    { token: 'good', orgId: 'o1' },
    { token: 'revoked', orgId: 'o1' },
    { token: 'revoked', orgId: 'o1' },
    { token: 'flaky', orgId: 'o1' },
    { token: 'moved', orgId: 'o1' },
  ];
  const closed = [];
  const revalidate = async (token) => {
    if (token === 'good') return 'o1';
    if (token === 'revoked') return null;
    if (token === 'moved') return 'o2';
    throw new Error('network');
  };
  const count = await revalidateConnections(sockets, revalidate, (ws) => closed.push(ws));
  assert.equal(count, 3);
  assert.equal(closed.filter((ws) => ws.token === 'revoked').length, 2);
  assert.equal(closed.filter((ws) => ws.token === 'moved').length, 1);
});
