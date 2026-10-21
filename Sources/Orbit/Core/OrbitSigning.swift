// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Orbit Authors

import Foundation

enum OrbitSigning {
    /// Apple Developer Team ID that signs Orbit releases. Empty until the
    /// project has a Developer ID: no signature then matches, so the fan
    /// helper and the in-place updater both fail closed, and updates open
    /// the release page instead.
    static let teamID = ""
}
