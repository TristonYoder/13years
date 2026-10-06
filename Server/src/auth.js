// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

const PLOTIPHAR_API_BASE = process.env.PLOTIPHAR_API_BASE || 'https://plotiphar.com';
const CACHE_TTL_MS = 60_000;
const USER_AGENT = 'ThirteenYearsRelay/1 (+https://plotiphar.com)';

const cache = new Map();

export async function resolveOrgIdForToken(token, fetchImpl = fetch) {
  const cached = cache.get(token);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.orgId;
  }

  const response = await fetchImpl(`${PLOTIPHAR_API_BASE}/api/organizations`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'User-Agent': USER_AGENT,
    },
  });

  if (!response.ok) {
    cache.delete(token);
    return null;
  }

  const org = await response.json();
  if (!org || typeof org.id !== 'string' || org.id.length === 0) {
    return null;
  }

  cache.set(token, { orgId: org.id, expiresAt: Date.now() + CACHE_TTL_MS });
  return org.id;
}

export function clearAuthCache() {
  cache.clear();
}
