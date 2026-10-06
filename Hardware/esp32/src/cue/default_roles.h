// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

#pragma once

struct DefaultRole {
  const char *id;
  const char *name;
};

static const DefaultRole kDefaultRoles[] = {
  {"default", "Default"},
};
static const int kDefaultRoleCount = sizeof(kDefaultRoles) / sizeof(kDefaultRoles[0]);
