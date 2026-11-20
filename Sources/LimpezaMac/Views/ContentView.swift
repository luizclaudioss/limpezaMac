import SwiftUI

struct ContentView: View {
    @StateObject private var vm = CleanerViewModel()

    var body: some View {
        NavigationSplitView {
            sidebarView
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 300)
        } detail: {
            detailView
        }
        .frame(minWidth: 920, minHeight: 620)
        .sheet(isPresented: $vm.showConfirmSheet) {
            ConfirmCleanupSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showResultSheet) {
            if let result = vm.lastCleanResult {
                CleanResultSheet(result: result) {
                    vm.openFullDiskAccessSettings()
                }
            }
        }
    }

    // MARK: - Sidebar
    private var sidebarView: some View {
        VStack(spacing: 0) {
            List(selection: $vm.selectedCategory) {
                Section("Visão Geral") {
                    HStack {
                        Label("Todos os Itens", systemImage: "tray.full.fill")
                        Spacer()
                        if vm.hasScanned {
                            Text(ByteCountFormatter.string(fromByteCount: vm.totalFoundBytes, countStyle: .file))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(Optional<CleanupCategory>.none)
                }

                Section("Categorias") {
                    ForEach(CleanupCategory.allCases) { category in
                        HStack {
                            Label(category.rawValue, systemImage: category.icon)
                            Spacer()
                            let bytes = vm.totalBytes(for: category)
                            let count = vm.count(for: category)
                            if bytes > 0 {
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else if count > 0 {
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(category))
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Disk Space Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(.blue)
                    Text("Armazenamento Mac")
                        .font(.caption.bold())
                    Spacer()
                    Text("\(vm.diskInfo.formattedAvailable) livre")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: vm.diskInfo.usedFraction)
                    .tint(vm.diskInfo.usedFraction > 0.85 ? .red : .blue)
            }
            .padding(12)
        }
    }

    // MARK: - Detail View
    private var detailView: some View {
        VStack(spacing: 0) {
            headerBanner

            if !vm.hasFullDiskAccess {
                fullDiskAccessBanner
            }

            if vm.isScanning {
                scanningView
            } else if !vm.hasScanned {
                emptyWelcomeView
            } else if vm.filteredItems.isEmpty {
                noItemsFoundView
            } else {
                itemsListView
            }

            Divider()
            bottomActionBar
        }
        .searchable(text: $vm.searchText, prompt: "Buscar por nome ou caminho...")
    }

    private var headerBanner: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.selectedCategory?.rawValue ?? "Limpeza Profunda do Mac")
                    .font(.title2.bold())
                Text(vm.selectedCategory?.description ?? "Escaneia caches, temporários, logs, sobras de apps, dev caches e snapshots com suporte a privilégios ROOT.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                vm.startScan()
            } label: {
                Label(vm.isScanning ? "Escaneando..." : "Escanear Mac", systemImage: "magnifyingglass")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isScanning || vm.isCleaning)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
            Text("Para escanear e limpar caches do Safari e pastas protegidas, clique em \"+\" em Acesso Total ao Disco e adicione o LimpezaMac.app.")
                .font(.caption)
            Spacer()
            Button("Mostrar App no Finder") {
                vm.revealInFinder(Bundle.main.bundlePath)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            Button("Abrir Ajustes") {
                vm.openFullDiskAccessSettings()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.3)
            Text(vm.scanStatus)
                .font(.headline)
            Text("Calculando tamanhos em disco (modo Dry-Run, nenhum arquivo será alterado)...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyWelcomeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)
            Text("Pronto para uma Limpeza Profunda")
                .font(.title2.bold())
            Text("Clique em \"Escanear Mac\" para analisar caches, logs, temporários, sobras de apps e snapshots.\nNada será apagado sem sua confirmação e senha.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button {
                vm.startScan()
            } label: {
                Label("Iniciar Scan (Dry-Run)", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noItemsFoundView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Nenhum item encontrado nesta visualização")
                .font(.headline)
            Text("Seu Mac está limpo nesta categoria ou o filtro de busca não retornou resultados.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemsListView: some View {
        VStack(spacing: 0) {
            // Selection toolbar
            HStack(spacing: 12) {
                Button("Selecionar Todos") {
                    vm.selectAllInCurrentView(true)
                }
                .buttonStyle(.link)
                .font(.caption)

                Button("Desmarcar Todos") {
                    vm.selectAllInCurrentView(false)
                }
                .buttonStyle(.link)
                .font(.caption)

                Button("Apenas Seguros") {
                    vm.selectSafeOnly()
                }
                .buttonStyle(.link)
                .font(.caption)

                Spacer()

                Text("\(vm.filteredItems.count) itens exibidos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            List {
                ForEach(vm.filteredItems) { item in
                    CleanupItemRow(
                        item: item,
                        onToggle: { vm.toggleItem(item.id) },
                        onReveal: { vm.revealInFinder(item.path) }
                    )
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var bottomActionBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selecionado: \(ByteCountFormatter.string(fromByteCount: vm.selectedBytes, countStyle: .file)) (\(vm.selectedItems.count) itens)")
                    .font(.headline.monospacedDigit())
                if vm.selectedRootCount > 0 {
                    Text("\(vm.selectedRootCount) item(ns) exigem privilégios ROOT (autenticação do macOS)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Modo Dry-Run ativo — revise antes de limpar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if vm.isCleaning {
                ProgressView()
                    .controlSize(.small)
                Text("Limpando...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                vm.showConfirmSheet = true
            } label: {
                Label("Limpar Selecionados", systemImage: "trash.fill")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(vm.selectedItems.isEmpty || vm.isScanning || vm.isCleaning)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CleanupItemRow: View {
    let item: CleanupItem
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Text(item.safetyLevel.rawValue)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.safetyLevel.color.opacity(0.15))
                        .foregroundStyle(item.safetyLevel.color)
                        .clipShape(Capsule())

                    if item.requiresRoot {
                        Text("ROOT")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }

                Text(item.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !item.isTimeMachineSnapshot {
                Button {
                    onReveal()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Mostrar no Finder")
            }

            Text(item.isTimeMachineSnapshot ? "Purgável" : item.formattedSize)
                .font(.body.monospacedDigit().bold())
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
