// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveOrgIdForToken, revalidateToken, clearAuthCache } from './auth.js';

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

test('negatively caches a failed lookup briefly', async () => {
  clearAuthCache();
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    return { ok: false, status: 401, json: async () => ({}) };
  };

  assert.equal(await resolveOrgIdForToken('fails-token', fetchImpl), null);
  assert.equal(await resolveOrgIdForToken('fails-token', fetchImpl), null);

  assert.equal(calls, 1);
});

test('passes an abort signal and times out a hung lookup', async () => {
  clearAuthCache();
  let sawSignal = false;
  const fetchImpl = (url, init) => {
    sawSignal = init.signal instanceof AbortSignal;
    return new Promise((resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(init.signal.reason));
    });
  };

  await assert.rejects(resolveOrgIdForToken('slow-token', fetchImpl, { timeoutMs: 20 }));
  assert.ok(sawSignal);
});

test('revalidateToken bypasses the cache and reports revocation', async () => {
  clearAuthCache();
  let ok = true;
  const fetchImpl = async () =>
    ok ? { ok: true, json: async () => ({ id: 'org_r' }) } : { ok: false, json: async () => ({}) };

  assert.equal(await resolveOrgIdForToken('re-token', fetchImpl), 'org_r');
  ok = false;
  assert.equal(await resolveOrgIdForToken('re-token', fetchImpl), 'org_r');
  assert.equal(await revalidateToken('re-token', fetchImpl), null);
  assert.equal(await resolveOrgIdForToken('re-token', fetchImpl), null);
});
