// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Orbit Authors

import Foundation

/// Label of the panel footer button that opens Orbit's maintenance window
/// (Dashboard, Energy, Cleanup, Disk Analyzer, Applications, Maintenance,
/// Processes, History).
enum MaintenanceWindowStrings {
    static func button(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Maintenance"
        case .ptBR: return "Manutenção"
        case .tr: return "Bakım"
        case .ru: return "Обслуживание"
        case .es: return "Mantenimiento"
        case .sk: return "Údržba"
        case .de: return "Wartung"
        case .fr: return "Maintenance"
        case .it: return "Manutenzione"
        case .ja: return "メンテナンス"
        case .ko: return "유지 관리"
        case .uk: return "Обслуговування"
        case .zhHans: return "维护"
        case .zhTW, .zhHK: return "維護"
        }
    }
}
