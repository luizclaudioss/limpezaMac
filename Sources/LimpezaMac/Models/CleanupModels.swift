import Foundation
import SwiftUI

enum CleanupCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case userCaches = "Caches de Usuário"
    case systemCaches = "Caches do Sistema"
    case tempAndLogs = "Temporários e Logs"
    case appLeftovers = "Sobras de Apps"
    case devCaches = "Caches de Dev"
    case browserCaches = "Navegadores"
    case trashAndDownloads = "Lixeira e Downloads"
    case timeMachineSnapshots = "Time Machine"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .userCaches: return "internaldrive"
        case .systemCaches: return "gearshape.2.fill"
        case .tempAndLogs: return "doc.text.magnifyingglass"
        case .appLeftovers: return "app.badge.checkmark"
        case .devCaches: return "hammer.fill"
        case .browserCaches: return "globe"
        case .trashAndDownloads: return "trash.fill"
        case .timeMachineSnapshots: return "clock.arrow.circlepath"
        }
    }

    var description: String {
        switch self {
        case .userCaches:
            return "Caches de aplicativos em ~/Library/Caches que podem ser recriados automaticamente."
        case .systemCaches:
            return "Caches globais em /Library/Caches e /private/var/folders (requer ROOT)."
        case .tempAndLogs:
            return "Arquivos temporários antigos (/tmp, /var/tmp) e logs de sistema/usuário."
        case .appLeftovers:
            return "Pastas e preferências órfãs de aplicativos que já foram desinstalados."
        case .devCaches:
            return "Xcode DerivedData, Simulators, Homebrew, npm, pip, uv, CocoaPods, Gradle e Cargo."
        case .browserCaches:
            return "Caches temporários do Safari, Chrome, Edge, Firefox e Brave."
        case .trashAndDownloads:
            return "Conteúdo da Lixeira e arquivos na pasta Downloads sem modificação há mais de 30 dias."
        case .timeMachineSnapshots:
            return "Snapshots locais APFS do Time Machine ocupando espaço purgável no disco."
        }
    }
}

enum SafetyLevel: String, Sendable, Comparable, Hashable {
    case safe = "Seguro"
    case moderate = "Moderado"
    case caution = "Atenção"

    var sortOrder: Int {
        switch self {
        case .safe: return 0
        case .moderate: return 1
        case .caution: return 2
        }
    }

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .moderate: return .orange
        case .caution: return .red
        }
    }
}

struct CleanupItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let sizeBytes: Int64
    let category: CleanupCategory
    let safetyLevel: SafetyLevel
    let requiresRoot: Bool
    let details: String
    let isTimeMachineSnapshot: Bool
    let snapshotDate: String?
    var isSelected: Bool

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        sizeBytes: Int64,
        category: CleanupCategory,
        safetyLevel: SafetyLevel,
        requiresRoot: Bool,
        details: String,
        isTimeMachineSnapshot: Bool = false,
        snapshotDate: String? = nil,
        isSelected: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.category = category
        self.safetyLevel = safetyLevel
        self.requiresRoot = requiresRoot
        self.details = details
        self.isTimeMachineSnapshot = isTimeMachineSnapshot
        self.snapshotDate = snapshotDate
        // Caution items (like old downloads or app leftovers) start unchecked by default for safety
        self.isSelected = isSelected ?? (safetyLevel != .caution)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct DiskSpaceInfo: Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
    let usedBytes: Int64

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

struct CleanItemFailure: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let reason: String
}

struct CleanResult: Sendable {
    let totalFreedBytes: Int64
    let removedCount: Int
    let failures: [CleanItemFailure]
    let wasCancelledByUser: Bool

    var formattedFreed: String {
        ByteCountFormatter.string(fromByteCount: totalFreedBytes, countStyle: .file)
    }
}
