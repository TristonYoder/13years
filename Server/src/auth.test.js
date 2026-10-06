// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveOrgIdForToken, clearAuthCache } from './auth.js';

function fakeFetch(response) {
  return async () => response;
}

test('resolves an org id from a 200 with a valid org body', async () => {
  clearAuthCache();
  const fetchImpl = fakeFetch({
    ok: true,
    json: async () => ({ id: 'org_abc123', name: 'Test Org' }),
  });

  const orgId = await resolveOrgIdForToken('good-token', fetchImpl);
  assert.equal(orgId, 'org_abc123');
});

test('returns null for a non-2xx response', async () => {
  clearAuthCache();
  const fetchImpl = fakeFetch({ ok: false, status: 401, json: async () => ({}) });

  const orgId = await resolveOrgIdForToken('bad-token', fetchImpl);
  assert.equal(orgId, null);
});

test('returns null when the body has no usable id', async () => {
  clearAuthCache();
  const fetchImpl = fakeFetch({ ok: true, json: async () => ({ name: 'No id here' }) });

  const orgId = await resolveOrgIdForToken('weird-token', fetchImpl);
  assert.equal(orgId, null);
});

test('caches a successful lookup so a second call skips the network', async () => {
  clearAuthCache();
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    return { ok: true, json: async () => ({ id: 'org_cached' }) };
  };

  const first = await resolveOrgIdForToken('cache-token', fetchImpl);
  const second = await resolveOrgIdForToken('cache-token', fetchImpl);

  assert.equal(first, 'org_cached');
  assert.equal(second, 'org_cached');
  assert.equal(calls, 1);
});

test('does not cache a failed lookup', async () => {
  clearAuthCache();
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    return { ok: false, status: 401, json: async () => ({}) };
  };

  await resolveOrgIdForToken('fails-token', fetchImpl);
  await resolveOrgIdForToken('fails-token', fetchImpl);

  assert.equal(calls, 2);
});
