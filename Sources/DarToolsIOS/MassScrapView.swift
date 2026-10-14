import SwiftUI

// Port MassScrapActivity.kt — "Masowe złomowanie" (z Podręcznej listy części).
// Pominięte: Snackbar (zastąpiony toastem).
struct MassScrapView: View {
    let db: String
    let user: User
    let ids: [String]

    @ObservedObject private var net = NetworkStatus.shared

    private var apiAddress: String { Prefs.apiAddress }
    private var helper: String { Prefs.apilohelperApi }

    enum Status { case idle, pending, success, failed }

    struct Item: Identifiable {
        let id: String
        var status: Status = .idle
        var message: String?
    }

    @State private var items: [Item] = []
    @State private var processing = false
    @State private var processedCount = 0
    @State private var helperLoading = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("\(user.name) / \(db)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            if processing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Przetwarzanie \(processedCount)/\(items.count)")
                        .font(.subheadline)
                }
                .padding(.vertical, 6)
            }

            if items.isEmpty {
                Spacer()
                Text("Brak elementów do złomowania")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(items) { item in
                    row(for: item)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Masowe złomowanie")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toast($toast)
        .task {
            items = ids.map { Item(id: $0) }
        }
    }

    // MARK: - Wiersz
    private func row(for item: Item) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ID: \(item.id)")
                if let m = item.message {
                    Text(m)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch item.status {
            case .idle:
                Color.clear.frame(width: 20, height: 20)
            case .pending:
                ProgressView().controlSize(.small)
            case .success:
                Image(systemName: "checkmark")
                    .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.19))
            case .failed:
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(rowBackground(item.status), in: .rect(cornerRadius: 8))
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }

    private func rowBackground(_ status: Status) -> Color {
        switch status {
        case .success: return Color(red: 0.87, green: 0.94, blue: 0.85) // 0xFFDFF0D8
        case .failed: return Color(red: 0.97, green: 0.84, blue: 0.85) // 0xFFF8D7DA
        default: return Color(.secondarySystemBackground)
        }
    }

    // MARK: - Dolny pasek
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if !processing, !helper.isEmpty, items.contains(where: { $0.status == .failed }) {
                Button {
                    runHelper()
                } label: {
                    HStack(spacing: 6) {
                        if helperLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Pomusz")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(height: 52)
                    .padding(.horizontal, 18)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(helperLoading)
            }

            PrimaryActionBar(
                title: "Rozpocznij złomowanie",
                systemImage: "flame.fill",
                isLoading: processing,
                disabled: items.isEmpty || processing || helperLoading
            ) { runScrap() }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Logika
    private func runScrap() {
        processing = true
        processedCount = 0
        Task {
            var succeeded: [String] = []
            for i in items.indices {
                items[i].status = .pending
                items[i].message = nil
                do {
                    let resp = try await PartApi.scrap(
                        api: apiAddress, db: db, login: user.name, password: user.password,
                        code: items[i].id
                    )
                    let kod = (resp["kod"] as? NSNumber)?.intValue ?? -1
                    let kom = (resp["komunikat"] as? String) ?? ""
                    if (200...299).contains(kod) {
                        items[i].status = .success
                        items[i].message = kom.isEmpty ? "OK" : kom
                        succeeded.append(items[i].id)
                    } else {
                        items[i].status = .failed
                        items[i].message = kom.isEmpty ? "Błąd: \(kod)" : kom
                    }
                } catch let e {
                    items[i].status = .failed
                    items[i].message = e.localizedDescription
                }
                processedCount = i + 1
            }
            // usuń ze wspólnej listy udane pozycje
            if !succeeded.isEmpty {
                QuickParts.removeIds(user: user.name, db: db, ids: succeeded)
            }
            processing = false
            toast = "Zakończono: \(processedCount)/\(items.count)"
        }
    }

    private func runHelper() {
        helperLoading = true
        Task {
            for i in items.indices where items[i].status == .failed {
                items[i].status = .pending
                items[i].message = nil
                do {
                    let resp = try await PartApi.scrapHelper(
                        helper: helper, db: db, login: user.name, password: user.password,
                        id: items[i].id
                    )
                    var displayed = ""
                    let raw = (((resp["scrapResult"] as? String) ?? "").trimmingCharacters(in: .whitespaces))
                    if !raw.isEmpty {
                        if let data = raw.data(using: .utf8),
                           let inner = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            displayed = (inner["komunikat"] as? String) ?? raw
                        } else {
                            displayed = raw
                        }
                    } else if let kom = resp["komunikat"] as? String {
                        displayed = kom
                    }
                    if displayed.contains("Zezłomowano część") {
                        items[i].status = .success
                        items[i].message = displayed.isEmpty ? "OK" : displayed
                    } else {
                        items[i].status = .failed
                        items[i].message = displayed.isEmpty ? "Brak informacji z helpera" : displayed
                    }
                } catch let e {
                    items[i].status = .failed
                    items[i].message = e.localizedDescription
                }
            }
            helperLoading = false
        }
    }
}
