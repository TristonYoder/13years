// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { joinRoom, relay, roomSize, roomCount, isRoomFull, MAX_CONNECTIONS_PER_ORG } from './rooms.js';

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

test('v2 sync packets pass through byte-for-byte, as binary frames', () => {
  const sender = fakeSocket();
  const receiver = fakeSocket();
  const orgId = 'org_test_v2_passthrough';
  joinRoom(orgId, sender);
  joinRoom(orgId, receiver);

  const packets = [
    { type: 'SYNC', senderId: 'p', t0: 1760000000000 },
    { type: 'SYNC_REPLY', senderId: 'h', t0: 1760000000000, t1: 1760000000010, t2: 1760000000011 },
    { type: 'TIMER_ANCHOR', senderId: 'h', rev: 4, anchor: null },
    { type: 'CUE_DELTA', senderId: 'h', rev: 5, cueDeltas: [{ id: 'host', state: 'GO', lastUpdated: 1 }] },
    { type: 'DIGEST', senderId: 'h', rev: 5, digestMs: 1760000000000, hashes: { roles: 'a', timer: 'b', messages: 'c' } },
    { type: 'PING', senderId: 'p', proto: 2 },
  ];
  for (const packet of packets) {
    relay(orgId, sender, Buffer.from(JSON.stringify(packet)), true);
  }

  assert.equal(receiver.sent.length, packets.length);
  receiver.sent.forEach((entry, index) => {
    assert.equal(entry.binary, true);
    assert.deepEqual(JSON.parse(entry.data.toString()), packets[index]);
  });
});

test('refuses connections beyond the per-org cap', () => {
  const orgId = 'org_test_cap';
  const leaves = [];
  for (let i = 0; i < MAX_CONNECTIONS_PER_ORG; i++) leaves.push(joinRoom(orgId, fakeSocket()));
  assert.ok(leaves.every((leave) => typeof leave === 'function'));
  assert.equal(isRoomFull(orgId), true);
  assert.equal(joinRoom(orgId, fakeSocket()), null);
  leaves[0]();
  assert.equal(isRoomFull(orgId), false);
  leaves.slice(1).forEach((leave) => leave());
});

test('drops slow consumers whose send buffer is too large', () => {
  const orgId = 'org_test_slow';
  const sender = fakeSocket();
  const slow = fakeSocket();
  slow.bufferedAmount = 3 * 1024 * 1024;
  let terminated = false;
  slow.terminate = () => {
    terminated = true;
  };
  const fast = fakeSocket();
  fast.bufferedAmount = 10;
  const leaves = [joinRoom(orgId, sender), joinRoom(orgId, slow), joinRoom(orgId, fast)];

  const delivered = relay(orgId, sender, Buffer.from('x'), true);

  assert.equal(delivered, 1);
  assert.equal(terminated, true);
  assert.equal(slow.sent.length, 0);
  assert.equal(fast.sent.length, 1);
  leaves.forEach((leave) => leave());
});
