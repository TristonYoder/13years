// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Triston Yoder

import os

public enum AppLog {
    public static let networking = Logger(subsystem: "dev.7co.13years", category: "networking")
    public static let cue = Logger(subsystem: "dev.7co.13years", category: "cue")
    public static let bridge = Logger(subsystem: "dev.7co.13years", category: "bridge")
}
