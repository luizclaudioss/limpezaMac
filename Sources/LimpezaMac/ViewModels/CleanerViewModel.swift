import Foundation
import SwiftUI

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var items: [CleanupItem] = []
    @Published var selectedCategory: CleanupCategory? = nil // nil = All categories
    @Published var searchText: String = ""
    @Published var isScanning: Bool = false
    @Published var isCleaning: Bool = false
    @Published var scanStatus: String = "Pronto para escanear"
    @Published var hasScanned: Bool = false
    @Published var diskInfo: DiskSpaceInfo = DiskScanner.getDiskSpaceInfo()
    @Published var hasFullDiskAccess: Bool = DiskScanner.hasFullDiskAccess()

    @Published var showConfirmSheet: Bool = false
    @Published var lastCleanResult: CleanResult? = nil
    @Published var showResultSheet: Bool = false

    private let scanner = DiskScanner()
    private let cleaner = RootCleaner()

    var filteredItems: [CleanupItem] {
        items.filter { item in
            let matchesCategory = (selectedCategory == nil || item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchText)
                || item.path.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var totalFoundBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedItems: [CleanupItem] {
        items.filter { $0.isSelected }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedRootCount: Int {
        selectedItems.filter { $0.requiresRoot || $0.isTimeMachineSnapshot }.count
    }

    func totalBytes(for category: CleanupCategory) -> Int64 {
        items.filter { $0.category == category }.reduce(0) { $0 + $1.sizeBytes }
    }

    func count(for category: CleanupCategory) -> Int {
        items.filter { $0.category == category }.count
    }

    func startScan() {
        guard !isScanning && !isCleaning else { return }
        isScanning = true
        hasScanned = false
        items = []
        diskInfo = DiskScanner.getDiskSpaceInfo()
        hasFullDiskAccess = DiskScanner.hasFullDiskAccess()

        Task {
            let found = await scanner.scanAll { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.scanStatus = status
                }
            }
            self.items = found
            self.isScanning = false
            self.hasScanned = true
            self.diskInfo = DiskScanner.getDiskSpaceInfo()
        }
    }

    func toggleItem(_ id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isSelected.toggle()
        }
    }

    func selectSafeOnly() {
        for idx in items.indices {
            items[idx].isSelected = (items[idx].safetyLevel == .safe)
        }
    }

    func selectAllInCurrentView(_ select: Bool) {
        let visibleIDs = Set(filteredItems.map { $0.id })
        for idx in items.indices where visibleIDs.contains(items[idx].id) {
            items[idx].isSelected = select
        }
    }

    func performCleanup() {
        let toClean = selectedItems
        guard !toClean.isEmpty else { return }
        showConfirmSheet = false
        isCleaning = true

        Task {
            let result = await cleaner.clean(items: toClean)
            self.isCleaning = false
            self.lastCleanResult = result
            self.showResultSheet = true

            if !result.wasCancelledByUser {
                let failedPaths = Set(result.failures.map { $0.path })
                let cleanedIDs = Set(toClean.filter { !failedPaths.contains($0.path) }.map { $0.id })
                self.items.removeAll { cleanedIDs.contains($0.id) }
            }
            self.diskInfo = DiskScanner.getDiskSpaceInfo()
        }
    }

    func revealInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
