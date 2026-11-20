import Foundation

final class RootCleaner: Sendable {
    private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

    func clean(items: [CleanupItem]) async -> CleanResult {
        let userItems = items.filter { !$0.requiresRoot && !$0.isTimeMachineSnapshot }
        let rootItems = items.filter { $0.requiresRoot || $0.isTimeMachineSnapshot }

        var freedBytes: Int64 = 0
        var removedCount = 0
        var failures: [CleanItemFailure] = []
        var cancelledByUser = false

        // 1. Clean user-level items directly
        for item in userItems {
            guard isPathSafeToDelete(item.path) else {
                failures.append(CleanItemFailure(name: item.name, path: item.path, reason: "Caminho bloqueado pela proteção de segurança."))
                continue
            }

            do {
                if item.path == "\(homeDir)/.Trash" {
                    try emptyDirectoryContents(atPath: item.path)
                } else {
                    try FileManager.default.removeItem(atPath: item.path)
                }
                freedBytes += item.sizeBytes
                removedCount += 1
            } catch {
                failures.append(CleanItemFailure(name: item.name, path: item.path, reason: error.localizedDescription))
            }
        }

        // 2. Clean root-level items & Time Machine snapshots via macOS admin privileges
        if !rootItems.isEmpty {
            let rootOutcome = executeRootCleanup(items: rootItems)
            freedBytes += rootOutcome.totalFreedBytes
            removedCount += rootOutcome.removedCount
            failures.append(contentsOf: rootOutcome.failures)
            cancelledByUser = rootOutcome.wasCancelledByUser
        }

        return CleanResult(
            totalFreedBytes: freedBytes,
            removedCount: removedCount,
            failures: failures,
            wasCancelledByUser: cancelledByUser
        )
    }

    private func emptyDirectoryContents(atPath path: String) throws {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(atPath: path)
        for entry in entries {
            try fm.removeItem(atPath: "\(path)/\(entry)")
        }
    }

    private func executeRootCleanup(items: [CleanupItem]) -> CleanResult {
        let scriptID = UUID().uuidString
        let scriptPath = "/tmp/limpezamac_clean_\(scriptID).sh"

        var scriptLines: [String] = [
            "#!/bin/bash",
            "set +e"
        ]

        var validItems: [CleanupItem] = []
        var failures: [CleanItemFailure] = []

        for (index, item) in items.enumerated() {
            if item.isTimeMachineSnapshot, let date = item.snapshotDate {
                // Validate snapshot date contains only digits and dashes
                let allowed = CharacterSet(charactersIn: "0123456789-")
                if date.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
                    validItems.append(item)
                    scriptLines.append("if /usr/bin/tmutil deletelocalsnapshots '\(date)' >/dev/null 2>&1; then echo \"OK:\(index)\"; else echo \"ERR:\(index):Falha ao remover snapshot\"; fi")
                } else {
                    failures.append(CleanItemFailure(name: item.name, path: item.path, reason: "Formato de snapshot inválido."))
                }
            } else if isPathSafeToDelete(item.path) {
                validItems.append(item)
                let escaped = shellSingleQuote(item.path)
                scriptLines.append("if /bin/rm -rf \(escaped) 2>/tmp/limpezamac_err_\(index); then echo \"OK:\(index)\"; else echo \"ERR:\(index):$(cat /tmp/limpezamac_err_\(index) | tr '\\n' ' ')\"; fi; /bin/rm -f /tmp/limpezamac_err_\(index)")
            } else {
                failures.append(CleanItemFailure(name: item.name, path: item.path, reason: "Caminho bloqueado pela proteção de segurança."))
            }
        }

        guard !validItems.isEmpty else {
            return CleanResult(totalFreedBytes: 0, removedCount: 0, failures: failures, wasCancelledByUser: false)
        }

        let scriptContent = scriptLines.joined(separator: "\n") + "\n"
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
        } catch {
            return CleanResult(
                totalFreedBytes: 0,
                removedCount: 0,
                failures: [CleanItemFailure(name: "Script Root", path: scriptPath, reason: error.localizedDescription)],
                wasCancelledByUser: false
            )
        }

        defer {
            try? FileManager.default.removeItem(atPath: scriptPath)
        }

        let osaCommand = "do shell script \"/bin/bash \(scriptPath)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", osaCommand]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CleanResult(
                totalFreedBytes: 0,
                removedCount: 0,
                failures: [CleanItemFailure(name: "Execução Root", path: scriptPath, reason: error.localizedDescription)],
                wasCancelledByUser: false
            )
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutStr = String(data: outData, encoding: .utf8) ?? ""
        let stderrStr = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && (stderrStr.contains("-128") || stderrStr.lowercased().contains("cancel")) {
            return CleanResult(totalFreedBytes: 0, removedCount: 0, failures: failures, wasCancelledByUser: true)
        }

        var freedBytes: Int64 = 0
        var removedCount = 0

        let lines = stdoutStr.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("OK:"), let idx = Int(line.dropFirst(3)), idx < items.count {
                freedBytes += items[idx].sizeBytes
                removedCount += 1
            } else if line.hasPrefix("ERR:") {
                let parts = line.dropFirst(4).split(separator: ":", maxSplits: 1)
                if let first = parts.first, let idx = Int(first), idx < items.count {
                    let msg = parts.count > 1 ? String(parts[1]) : "Permissão negada ou arquivo em uso."
                    failures.append(CleanItemFailure(name: items[idx].name, path: items[idx].path, reason: msg))
                }
            }
        }

        if removedCount == 0 && failures.isEmpty && process.terminationStatus != 0 {
            failures.append(CleanItemFailure(name: "Privilégios Root", path: "/", reason: stderrStr.isEmpty ? "Falha na autenticação administrativa." : stderrStr))
        }

        return CleanResult(totalFreedBytes: freedBytes, removedCount: removedCount, failures: failures, wasCancelledByUser: false)
    }

    private func shellSingleQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    /// Strict allowlist of parent directories that LimpezaMac is ever permitted to delete inside.
    private func isPathSafeToDelete(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let forbiddenExact: Set<String> = [
            "/", "/System", "/usr", "/bin", "/sbin", "/Applications", "/Library",
            "/Users", homeDir, "\(homeDir)/Library", "\(homeDir)/Downloads",
            "/private", "/private/tmp", "/tmp", "/private/var", "/var",
            "/private/var/tmp", "/var/tmp",
            "/private/var/log", "/var/log",
            "/private/var/folders", "/var/folders"
        ]
        if forbiddenExact.contains(standardized) { return false }

        let allowedPrefixes = [
            "\(homeDir)/Library/Caches/",
            "\(homeDir)/Library/Logs/",
            "\(homeDir)/Library/Application Support/",
            "\(homeDir)/Library/Containers/",
            "\(homeDir)/Library/Saved Application State/",
            "\(homeDir)/Library/Developer/",
            "\(homeDir)/.npm/",
            "\(homeDir)/.cache/",
            "\(homeDir)/.pnpm-store",
            "\(homeDir)/.gradle/",
            "\(homeDir)/.cargo/",
            "\(homeDir)/Downloads/",
            "/Library/Caches/",
            "/Library/Logs/",
            "/Library/Application Support/",
            "/private/tmp/",
            "/tmp/",
            "/private/var/tmp/",
            "/var/tmp/",
            "/private/var/log/",
            "/var/log/",
            "/private/var/folders/",
            "/var/folders/"
        ]

        if standardized == "\(homeDir)/.Trash" { return true }
        return allowedPrefixes.contains { standardized.hasPrefix($0) }
    }
}
