import SwiftUI

struct ConfirmCleanupSheet: View {
    @ObservedObject var vm: CleanerViewModel
    @Environment(\.dismiss) private var dismiss

    private var cautionItems: [CleanupItem] {
        vm.selectedItems.filter { $0.safetyLevel == .caution }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirmar Limpeza Profunda")
                        .font(.title2.bold())
                    Text("Esta ação removerá permanentemente os itens selecionados.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    Text("Itens selecionados:")
                        .foregroundStyle(.secondary)
                    Text("\(vm.selectedItems.count) itens")
                        .bold()
                }
                GridRow {
                    Text("Espaço a liberar:")
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: vm.selectedBytes, countStyle: .file))
                        .bold()
                        .foregroundStyle(.green)
                }
                GridRow {
                    Text("Itens com privilégio ROOT:")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("\(vm.selectedRootCount)")
                            .bold()
                        if vm.selectedRootCount > 0 {
                            Text("(Solicitará senha de administrador)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !cautionItems.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Você selecionou \(cautionItems.count) item(ns) marcados como \"Atenção\" (ex: sobras de apps ou downloads antigos). Certifique-se de que não precisa deles.")
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            HStack {
                Button("Cancelar") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    vm.performCleanup()
                } label: {
                    Label(
                        vm.selectedRootCount > 0 ? "Autorizar (ROOT) e Limpar" : "Limpar Agora",
                        systemImage: vm.selectedRootCount > 0 ? "lock.open.fill" : "trash.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 340)
    }
}

struct CleanResultSheet: View {
    let result: CleanResult
    let onOpenFDA: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: result.wasCancelledByUser ? "xmark.circle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(result.wasCancelledByUser ? .orange : .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.wasCancelledByUser ? "Autenticação Cancelada" : "Limpeza Concluída")
                        .font(.title2.bold())
                    if result.wasCancelledByUser {
                        Text("A operação ROOT foi cancelada pelo usuário. Itens de usuário (se houver) foram processados.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Foram removidos \(result.removedCount) itens, liberando \(result.formattedFreed).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !result.failures.isEmpty {
                Divider()
                Text("Itens ignorados ou com erro (\(result.failures.count)):")
                    .font(.headline)

                List(result.failures) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.name)
                            .font(.subheadline.bold())
                        Text(failure.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(failure.reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("Se houver erros de permissão (TCC), conceda Acesso Total ao Disco:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Abrir Ajustes de Privacidade") {
                        onOpenFDA()
                    }
                    .font(.caption)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Fechar") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: result.failures.isEmpty ? 220 : 430)
    }
}
