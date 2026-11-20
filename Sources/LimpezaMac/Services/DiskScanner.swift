import Foundation

final class DiskScanner: Sendable {
    private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

    static func getDiskSpaceInfo() -> DiskSpaceInfo {
        let rootURL = URL(fileURLWithPath: "/")
        do {
            let values = try rootURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            let used = max(0, total - available)
            return DiskSpaceInfo(totalBytes: total, availableBytes: available, usedBytes: used)
        } catch {
            return DiskSpaceInfo(totalBytes: 0, availableBytes: 0, usedBytes: 0)
        }
    }

    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let safariDir = "\(home)/Library/Safari"
        if FileManager.default.fileExists(atPath: safariDir) {
            return (try? FileManager.default.contentsOfDirectory(atPath: safariDir)) != nil
        }
        let mailDir = "\(home)/Library/Mail"
        if FileManager.default.fileExists(atPath: mailDir) {
            return (try? FileManager.default.contentsOfDirectory(atPath: mailDir)) != nil
        }
        return true
    }

    func scanAll(onProgress: @Sendable (String) -> Void) async -> [CleanupItem] {
        var allItems: [CleanupItem] = []

        onProgress("Escaneando caches de usuário...")
        allItems.append(contentsOf: scanUserCaches())

        onProgress("Escaneando caches do sistema (Root)...")
        allItems.append(contentsOf: scanSystemCaches())

        onProgress("Escaneando arquivos temporários e logs...")
        allItems.append(contentsOf: scanTempAndLogs())

        onProgress("Detectando sobras de apps desinstalados...")
        allItems.append(contentsOf: scanAppLeftovers())

        onProgress("Escaneando caches de desenvolvimento...")
        allItems.append(contentsOf: scanDevCaches())

        onProgress("Escaneando caches de navegadores...")
        allItems.append(contentsOf: scanBrowserCaches())

        onProgress("Escaneando Lixeira e Downloads antigos...")
        allItems.append(contentsOf: scanTrashAndDownloads())

        onProgress("Verificando snapshots locais do Time Machine...")
        allItems.append(contentsOf: scanTimeMachineSnapshots())

        onProgress("Concluído")
        return allItems.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - 1. User Caches
    private func scanUserCaches() -> [CleanupItem] {
        let cachesPath = "\(homeDir)/Library/Caches"
        return scanTopLevelChildren(
            in: cachesPath,
            category: .userCaches,
            safetyLevel: .safe,
            requiresRoot: false,
            minBytes: 512_000, // >= 500 KB
            excludedNames: [
                "com.apple.Safari", "Google", "Microsoft Edge", "Firefox", "BraveSoftware",
                "Homebrew", "CocoaPods", "org.swift.swiftpm", "CloudKit", "com.apple.aned"
            ],
            detailsBuilder: { name in "Cache de usuário: \(name)" }
        )
    }

    // MARK: - 2. System Caches (Root)
    private func scanSystemCaches() -> [CleanupItem] {
        var items: [CleanupItem] = []
        let sysCaches = "/Library/Caches"
        items.append(contentsOf: scanTopLevelChildren(
            in: sysCaches,
            category: .systemCaches,
            safetyLevel: .safe,
            requiresRoot: true,
            minBytes: 512_000,
            excludedNames: ["com.apple.aned", "com.apple.iconservices.store"],
            detailsBuilder: { name in "Cache global do sistema: \(name)" }
        ))

        // /private/var/folders user temp/cache subfolders (C and T)
        let varFolders = "/private/var/folders"
        if let topDirs = try? FileManager.default.contentsOfDirectory(atPath: varFolders) {
            for top in topDirs where top != "zz" {
                let topPath = "\(varFolders)/\(top)"
                if let subDirs = try? FileManager.default.contentsOfDirectory(atPath: topPath) {
                    for sub in subDirs {
                        let cacheSub = "\(topPath)/\(sub)/C"
                        if FileManager.default.fileExists(atPath: cacheSub) {
                            let size = directorySize(atPath: cacheSub)
                            if size > 5_000_000 { // > 5 MB
                                items.append(CleanupItem(
                                    name: "macOS Var Cache (\(sub))",
                                    path: cacheSub,
                                    sizeBytes: size,
                                    category: .systemCaches,
                                    safetyLevel: .moderate,
                                    requiresRoot: true,
                                    details: "Cache temporário por usuário gerenciado pelo sistema em /private/var/folders"
                                ))
                            }
                        }
                    }
                }
            }
        }
        return items
    }

    // MARK: - 3. Temp & Logs
    private func scanTempAndLogs() -> [CleanupItem] {
        var items: [CleanupItem] = []

        // User Logs
        items.append(contentsOf: scanTopLevelChildren(
            in: "\(homeDir)/Library/Logs",
            category: .tempAndLogs,
            safetyLevel: .safe,
            requiresRoot: false,
            minBytes: 256_000,
            excludedNames: [],
            detailsBuilder: { name in "Logs de aplicativo do usuário: \(name)" }
        ))

        // System Logs (/Library/Logs)
        items.append(contentsOf: scanTopLevelChildren(
            in: "/Library/Logs",
            category: .tempAndLogs,
            safetyLevel: .safe,
            requiresRoot: true,
            minBytes: 256_000,
            excludedNames: [],
            detailsBuilder: { name in "Logs globais do sistema: \(name)" }
        ))

        // Rotated / archived logs in /private/var/log
        let varLog = "/private/var/log"
        if let logEntries = try? FileManager.default.contentsOfDirectory(atPath: varLog) {
            for entry in logEntries {
                let fullPath = "\(varLog)/\(entry)"
                let isArchivedLog = entry.hasSuffix(".gz") || entry.hasSuffix(".bz2") || entry.hasSuffix(".asl")
                if isArchivedLog || entry == "DiagnosticReports" {
                    let size = directorySize(atPath: fullPath)
                    if size > 256_000 {
                        items.append(CleanupItem(
                            name: "var/log/\(entry)",
                            path: fullPath,
                            sizeBytes: size,
                            category: .tempAndLogs,
                            safetyLevel: .safe,
                            requiresRoot: true,
                            details: "Logs arquivados ou relatórios de diagnóstico do sistema"
                        ))
                    }
                }
            }
        }

        // /private/tmp & /private/var/tmp (files older than 24h)
        let oneDayAgo = Date().addingTimeInterval(-86400)
        for tmpRoot in ["/private/tmp", "/private/var/tmp"] {
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: tmpRoot) {
                for entry in entries {
                    // Skip active sockets, X11, launchd, and our own temp files
                    if entry.hasPrefix("com.apple.launchd") || entry.hasPrefix(".X") || entry.hasPrefix("limpezamac_") {
                        continue
                    }
                    let fullPath = "\(tmpRoot)/\(entry)"
                    guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) else { continue }
                    if let fileType = attrs[.type] as? FileAttributeType, fileType == .typeSocket {
                        continue
                    }
                    let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                    if modDate < oneDayAgo {
                        let size = directorySize(atPath: fullPath)
                        if size > 100_000 {
                            items.append(CleanupItem(
                                name: entry,
                                path: fullPath,
                                sizeBytes: size,
                                category: .tempAndLogs,
                                safetyLevel: .safe,
                                requiresRoot: true,
                                details: "Arquivo temporário sem modificação há mais de 24h em \(tmpRoot)"
                            ))
                        }
                    }
                }
            }
        }

        return items
    }

    // MARK: - 4. App Leftovers
    private func scanAppLeftovers() -> [CleanupItem] {
        let installed = collectInstalledAppIdentifiers()
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
        var items: [CleanupItem] = []

        let searchDirs: [(path: String, label: String, isRoot: Bool)] = [
            ("\(homeDir)/Library/Application Support", "Application Support", false),
            ("\(homeDir)/Library/Containers", "Container", false),
            ("\(homeDir)/Library/Saved Application State", "Saved State", false),
            ("/Library/Application Support", "Application Support (Sistema)", true)
        ]

        let systemSafeNames: Set<String> = [
            "apple", "mobilesync", "addressbook", "dock", "clouddocs", "fileprovider",
            "knowledge", "crashreporter", "cef", "icloud", "syncservices", "callhistorydb",
            "callhistorytransactions", "proactive", "spotlight", "animoji", "face",
            "script editor", "preview", "finder", "safari", "mail", "messages", "notes",
            "photos", "music", "tv", "podcasts", "books", "app store", "system"
        ]

        for (dirPath, label, isRoot) in searchDirs {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else { continue }
            for entry in entries {
                if entry.hasPrefix(".") || entry.hasPrefix("com.apple.") || entry.hasPrefix("group.com.apple.") {
                    continue
                }

                let normalized = normalizeAppToken(entry)
                if systemSafeNames.contains(normalized) { continue }
                if isMatchedByInstalledApp(token: normalized, rawName: entry, installed: installed) {
                    continue
                }

                let fullPath = "\(dirPath)/\(entry)"
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) else { continue }
                let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                if modDate > sevenDaysAgo { continue }

                let size = directorySize(atPath: fullPath)
                if size >= 1_000_000 { // >= 1 MB
                    items.append(CleanupItem(
                        name: entry,
                        path: fullPath,
                        sizeBytes: size,
                        category: .appLeftovers,
                        safetyLevel: .caution,
                        requiresRoot: isRoot,
                        details: "Possível sobra de app desinstalado (\(label)). Verifique antes de apagar."
                    ))
                }
            }
        }

        return items
    }

    // MARK: - 5. Dev Caches
    private func scanDevCaches() -> [CleanupItem] {
        let targets: [(name: String, path: String, safety: SafetyLevel, root: Bool, details: String)] = [
            ("Xcode DerivedData", "\(homeDir)/Library/Developer/Xcode/DerivedData", .safe, false, "Builds intermediários e índices do Xcode (recriado ao compilar)"),
            ("Xcode iOS DeviceSupport", "\(homeDir)/Library/Developer/Xcode/iOS DeviceSupport", .moderate, false, "Símbolos de debug de versões antigas do iOS"),
            ("Xcode Archives", "\(homeDir)/Library/Developer/Xcode/Archives", .caution, false, "Arquivos .xcarchive de builds publicados/exportados"),
            ("CoreSimulator Caches", "\(homeDir)/Library/Developer/CoreSimulator/Caches", .safe, false, "Caches de runtime do Simulador iOS"),
            ("Homebrew Cache (User)", "\(homeDir)/Library/Caches/Homebrew", .safe, false, "Pacotes baixados pelo Homebrew"),
            ("Homebrew Cache (System)", "/Library/Caches/Homebrew", .safe, true, "Pacotes globais baixados pelo Homebrew"),
            ("npm Cache", "\(homeDir)/.npm/_cacache", .safe, false, "Cache de pacotes do npm"),
            ("Yarn Cache", "\(homeDir)/.cache/yarn", .safe, false, "Cache de pacotes do Yarn"),
            ("pnpm Store", "\(homeDir)/.pnpm-store", .moderate, false, "Store de pacotes do pnpm"),
            ("pip Cache", "\(homeDir)/.cache/pip", .safe, false, "Cache de wheels e pacotes Python (pip)"),
            ("uv Cache", "\(homeDir)/.cache/uv", .safe, false, "Cache de pacotes Python (uv)"),
            ("CocoaPods Cache", "\(homeDir)/Library/Caches/CocoaPods", .safe, false, "Cache de pods do CocoaPods"),
            ("SwiftPM Cache", "\(homeDir)/Library/Caches/org.swift.swiftpm", .safe, false, "Cache de pacotes do Swift Package Manager"),
            ("Gradle Caches", "\(homeDir)/.gradle/caches", .moderate, false, "Cache de dependências do Gradle"),
            ("Cargo Registry Cache", "\(homeDir)/.cargo/registry/cache", .safe, false, "Cache de crates do Rust/Cargo")
        ]

        var items: [CleanupItem] = []
        for target in targets {
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let size = directorySize(atPath: target.path)
            if size >= 512_000 {
                items.append(CleanupItem(
                    name: target.name,
                    path: target.path,
                    sizeBytes: size,
                    category: .devCaches,
                    safetyLevel: target.safety,
                    requiresRoot: target.root,
                    details: target.details
                ))
            }
        }
        return items
    }

    // MARK: - 6. Browser Caches
    private func scanBrowserCaches() -> [CleanupItem] {
        var items: [CleanupItem] = []
        let targets: [(name: String, path: String, details: String)] = [
            ("Safari Cache", "\(homeDir)/Library/Caches/com.apple.Safari", "Cache de navegação do Safari"),
            ("Google Chrome Cache", "\(homeDir)/Library/Caches/Google/Chrome", "Cache de navegação do Google Chrome"),
            ("Microsoft Edge Cache", "\(homeDir)/Library/Caches/Microsoft Edge", "Cache de navegação do Microsoft Edge"),
            ("Brave Browser Cache", "\(homeDir)/Library/Caches/BraveSoftware", "Cache de navegação do Brave"),
            ("Firefox Cache", "\(homeDir)/Library/Caches/Firefox/Profiles", "Cache de navegação do Mozilla Firefox")
        ]

        for target in targets {
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let size = directorySize(atPath: target.path)
            if size >= 512_000 {
                items.append(CleanupItem(
                    name: target.name,
                    path: target.path,
                    sizeBytes: size,
                    category: .browserCaches,
                    safetyLevel: .safe,
                    requiresRoot: false,
                    details: target.details
                ))
            }
        }
        return items
    }

    // MARK: - 7. Trash & Old Downloads
    private func scanTrashAndDownloads() -> [CleanupItem] {
        var items: [CleanupItem] = []

        // Trash
        let trashPath = "\(homeDir)/.Trash"
        if FileManager.default.fileExists(atPath: trashPath) {
            let trashSize = directorySize(atPath: trashPath)
            if trashSize > 0 {
                items.append(CleanupItem(
                    name: "Lixeira do Usuário (~/.Trash)",
                    path: trashPath,
                    sizeBytes: trashSize,
                    category: .trashAndDownloads,
                    safetyLevel: .moderate,
                    requiresRoot: false,
                    details: "Arquivos atualmente na Lixeira aguardando exclusão permanente"
                ))
            }
        }

        // Old Downloads (> 30 days)
        let downloadsPath = "\(homeDir)/Downloads"
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: downloadsPath) {
            for entry in entries where !entry.hasPrefix(".") {
                let fullPath = "\(downloadsPath)/\(entry)"
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) else { continue }
                let modDate = (attrs[.modificationDate] as? Date) ?? Date()
                if modDate < thirtyDaysAgo {
                    let size = directorySize(atPath: fullPath)
                    if size >= 5_000_000 { // >= 5 MB
                        items.append(CleanupItem(
                            name: entry,
                            path: fullPath,
                            sizeBytes: size,
                            category: .trashAndDownloads,
                            safetyLevel: .caution,
                            requiresRoot: false,
                            details: "Item em ~/Downloads sem modificação há mais de 30 dias"
                        ))
                    }
                }
            }
        }

        return items
    }

    // MARK: - 8. Time Machine Local Snapshots
    private func scanTimeMachineSnapshots() -> [CleanupItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var items: [CleanupItem] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Example: com.apple.TimeMachine.2026-11-14-120000.local
            if trimmed.hasPrefix("com.apple.TimeMachine.") {
                let datePart = trimmed
                    .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                    .replacingOccurrences(of: ".local", with: "")
                items.append(CleanupItem(
                    name: "Snapshot \(datePart)",
                    path: trimmed,
                    sizeBytes: 0, // APFS snapshots share blocks; size is reclaimed dynamically
                    category: .timeMachineSnapshots,
                    safetyLevel: .moderate,
                    requiresRoot: true,
                    details: "Snapshot local APFS do Time Machine (libera espaço purgável ao remover)",
                    isTimeMachineSnapshot: true,
                    snapshotDate: datePart
                ))
            }
        }
        return items
    }

    // MARK: - Helpers
    private func scanTopLevelChildren(
        in directory: String,
        category: CleanupCategory,
        safetyLevel: SafetyLevel,
        requiresRoot: Bool,
        minBytes: Int64,
        excludedNames: Set<String>,
        detailsBuilder: (String) -> String
    ) -> [CleanupItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        var items: [CleanupItem] = []
        for entry in entries where !entry.hasPrefix(".") {
            if excludedNames.contains(entry) { continue }
            let fullPath = "\(directory)/\(entry)"
            let size = directorySize(atPath: fullPath)
            if size >= minBytes {
                items.append(CleanupItem(
                    name: entry,
                    path: fullPath,
                    sizeBytes: size,
                    category: category,
                    safetyLevel: safetyLevel,
                    requiresRoot: requiresRoot,
                    details: detailsBuilder(entry)
                ))
            }
        }
        return items
    }

    private func directorySize(atPath path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }

        let url = URL(fileURLWithPath: path)
        if !isDir.boolValue {
            let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey])
            if vals?.isSymbolicLink == true { return 0 }
            return Int64(vals?.totalFileAllocatedSize ?? vals?.fileSize ?? 0)
        }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else {
                continue
            }
            if vals.isSymbolicLink == true { continue }
            if vals.isRegularFile == true {
                total += Int64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
            }
        }
        return total
    }

    private func collectInstalledAppIdentifiers() -> Set<String> {
        var tokens: Set<String> = []
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "\(homeDir)/Applications"
        ]

        let fm = FileManager.default
        for dir in appDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appName = String(entry.dropLast(4))
                tokens.insert(normalizeAppToken(appName))

                let plistPath = "\(dir)/\(entry)/Contents/Info.plist"
                if let dict = NSDictionary(contentsOfFile: plistPath) {
                    if let bundleID = dict["CFBundleIdentifier"] as? String {
                        tokens.insert(normalizeAppToken(bundleID))
                        for part in bundleID.split(separator: ".") where part.count > 2 {
                            let partStr = String(part).lowercased()
                            if partStr != "com" && partStr != "org" && partStr != "net" && partStr != "app" {
                                tokens.insert(partStr)
                            }
                        }
                    }
                    if let bundleName = dict["CFBundleName"] as? String {
                        tokens.insert(normalizeAppToken(bundleName))
                    }
                }
            }
        }
        return tokens
    }

    private func normalizeAppToken(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: ".savedstate", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private func isMatchedByInstalledApp(token: String, rawName: String, installed: Set<String>) -> Bool {
        if installed.contains(token) { return true }
        for inst in installed where inst.count >= 4 {
            if token.contains(inst) || inst.contains(token) {
                return true
            }
        }
        // Check dot-separated parts of bundle IDs (e.g., com.company.app)
        for part in rawName.split(separator: ".") where part.count >= 4 {
            let p = String(part).lowercased()
            if p != "com" && p != "org" && p != "net" && p != "savedstate" && installed.contains(p) {
                return true
            }
        }
        return false
    }
}
