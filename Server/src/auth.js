// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

const PLOTIPHAR_API_BASE = process.env.PLOTIPHAR_API_BASE || 'https://plotiphar.com';
const CACHE_TTL_MS = 60_000;
const NEGATIVE_CACHE_TTL_MS = 5_000;
const LOOKUP_TIMEOUT_MS = 3_000;
const MAX_CACHE_ENTRIES = 10_000;
const USER_AGENT = 'ThirteenYearsRelay/1 (+https://plotiphar.com)';

const cache = new Map();
const negativeCache = new Map();

function prune(map, now) {
  for (const [key, entry] of map) {
    if (entry.expiresAt <= now) map.delete(key);
  }
  while (map.size >= MAX_CACHE_ENTRIES) {
    map.delete(map.keys().next().value);
  }
}

async function lookup(token, fetchImpl, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(new Error('Auth lookup timed out')), timeoutMs);
  try {
    const response = await fetchImpl(`${PLOTIPHAR_API_BASE}/api/organizations`, {
      headers: {
        Authorization: `Bearer ${token}`,
        'User-Agent': USER_AGENT,
      },
      signal: controller.signal,
    });

    if (!response.ok) {
      return { rejected: true, orgId: null };
    }

    const org = await response.json();
    if (!org || typeof org.id !== 'string' || org.id.length === 0) {
      return { rejected: true, orgId: null };
    }
    return { rejected: false, orgId: org.id };
  } finally {
    clearTimeout(timer);
  }
}

export async function resolveOrgIdForToken(token, fetchImpl = fetch, { timeoutMs = LOOKUP_TIMEOUT_MS } = {}) {
  const now = Date.now();
  const cached = cache.get(token);
  if (cached && cached.expiresAt > now) {
    return cached.orgId;
  }

  const denied = negativeCache.get(token);
  if (denied && denied.expiresAt > now) {
    return null;
  }

  const result = await lookup(token, fetchImpl, timeoutMs);
  const after = Date.now();

  if (result.rejected) {
    cache.delete(token);
    prune(negativeCache, after);
    negativeCache.set(token, { expiresAt: after + NEGATIVE_CACHE_TTL_MS });
    return null;
  }

  prune(cache, after);
  negativeCache.delete(token);
  cache.set(token, { orgId: result.orgId, expiresAt: after + CACHE_TTL_MS });
  return result.orgId;
}

export async function revalidateToken(token, fetchImpl = fetch, { timeoutMs = LOOKUP_TIMEOUT_MS } = {}) {
  const result = await lookup(token, fetchImpl, timeoutMs);
  const now = Date.now();
  if (result.rejected) {
    cache.delete(token);
    prune(negativeCache, now);
    negativeCache.set(token, { expiresAt: now + NEGATIVE_CACHE_TTL_MS });
    return null;
  }
  prune(cache, now);
  cache.set(token, { orgId: result.orgId, expiresAt: now + CACHE_TTL_MS });
  return result.orgId;
}

export function clearAuthCache() {
  cache.clear();
  negativeCache.clear();
}
