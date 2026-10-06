// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { joinRoom, relay, roomSize, roomCount } from './rooms.js';

function fakeSocket() {
  const sent = [];
  return {
    OPEN: 1,
    readyState: 1,
    send: (data, opts) => sent.push({ data, binary: opts?.binary }),
    sent,
  };
}

test('relay fans out to every other socket in the room, never the sender', () => {
  const a = fakeSocket();
  const b = fakeSocket();
  const c = fakeSocket();
  const orgId = 'org_test_fanout';

  joinRoom(orgId, a);
  joinRoom(orgId, b);
  joinRoom(orgId, c);

  const delivered = relay(orgId, a, Buffer.from('hello'), true);

  assert.equal(delivered, 2);
  assert.equal(a.sent.length, 0);
  assert.equal(b.sent.length, 1);
  assert.equal(c.sent.length, 1);
  assert.deepEqual(b.sent[0].data, Buffer.from('hello'));
  assert.equal(b.sent[0].binary, true);
});

test('rooms are isolated by orgId', () => {
  const a = fakeSocket();
  const b = fakeSocket();
  joinRoom('org_1', a);
  joinRoom('org_2', b);

  const delivered = relay('org_1', a, Buffer.from('x'), true);

  assert.equal(delivered, 0);
  assert.equal(b.sent.length, 0);
});

test('leave() removes the socket, and the room disappears once empty', () => {
  const a = fakeSocket();
  const b = fakeSocket();
  const orgId = 'org_leave';
  const countBefore = roomCount();

  const leaveA = joinRoom(orgId, a);
  const leaveB = joinRoom(orgId, b);
  assert.equal(roomSize(orgId), 2);

  leaveB();
  assert.equal(roomSize(orgId), 1);

  leaveA();
  assert.equal(roomSize(orgId), 0);
  assert.equal(roomCount(), countBefore);
});

test('a socket that is not OPEN is skipped, not delivered to', () => {
  const a = fakeSocket();
  const b = fakeSocket();
  b.readyState = 3;
  const orgId = 'org_closed';

  joinRoom(orgId, a);
  joinRoom(orgId, b);

  const delivered = relay(orgId, a, Buffer.from('x'), true);
  assert.equal(delivered, 0);
  assert.equal(b.sent.length, 0);
});
