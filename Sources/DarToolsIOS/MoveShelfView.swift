import SwiftUI

// Port MoveShelfActivity.kt — "Przenieś półkę".
// Pominięte: DataWedge, wewnętrzna klawiatura (systemowa), suppress/robust-focus
// (niepotrzebne bez natywnych EditText).
struct MoveShelfView: View {
    let db: String
    let user: User

    @ObservedObject private var net = NetworkStatus.shared

    private var apiAddress: String { Prefs.apiAddress }

    enum MoveStatus { case success, failed }
    enum Field: Hashable { case old, new }

    @State private var oldShelf = ""
    @State private var newShelf = ""
    @State private var lastFocused: Field = .old
    @FocusState private var focused: Field?
    @State private var loading = false
    @State private var assigning = false
    @State private var error: String?
    @State private var infoMessage: String?
    @State private var parts: [[String: Any]] = []
    @State private var statusMap: [String: MoveStatus] = [:]
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ID aktualnej półki")
                    .font(.caption)
                    .padding(.leading, 4)
                oldField
                Text("ID nowej półki")
                    .font(.caption)
                    .padding(.leading, 4)
                newField

                HStack(spacing: 8) {
                    Button("Wczytaj aktualną") { fetchOld() }
                        .buttonStyle(.glassProminent)
                        .disabled(loading || oldShelf.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Przenieś wszystkie") { assignAll() }
                        .buttonStyle(.glassProminent)
                        .disabled(assigning || parts.isEmpty || newShelf.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(12)

            if loading {
                ProgressView().padding(.bottom, 4)
            }
            if let e = error {
                Text(e)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            if let m = infoMessage {
                Text(m)
                    .foregroundStyle(.tint)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }

            List {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    partRow(p)
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
        .navigationTitle("Przenieś półkę")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focused) { _, f in if let f { lastFocused = f } }
        .overlay(alignment: .bottom) {
            CameraPill(showScanner: $showScanner, visible: focused == nil) { scanned in
                handleScan(scanned)
            }
        }
    }

    // MARK: - Pola
    private var oldField: some View {
        HStack {
            TextField("ID aktualnej półki", text: $oldShelf)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .focused($focused, equals: .old)
                .onChange(of: oldShelf) { _, v in
                    let f = PlaceOnShelfView.filterShelf(v)
                    if f != v { oldShelf = f }
                    error = nil
                }
                .onSubmit {
                    // jak Enter na Androidzie: tylko przejście na nową półkę, bez fetcha
                    let cleaned = PlaceOnShelfView.filterShelf(oldShelf)
                    guard !cleaned.isEmpty else { return }
                    oldShelf = cleaned
                    focused = .new
                    lastFocused = .new
                }
            if !oldShelf.isEmpty {
                Button {
                    oldShelf = ""
                    parts = []
                    statusMap = [:]
                    infoMessage = nil
                    error = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .inputFieldStyle()
    }

    private var newField: some View {
        HStack {
            TextField("ID nowej półki", text: $newShelf)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .focused($focused, equals: .new)
                .onChange(of: newShelf) { _, v in
                    let f = PlaceOnShelfView.filterShelf(v)
                    if f != v { newShelf = f }
                    error = nil
                }
            if !newShelf.isEmpty {
                Button { newShelf = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .inputFieldStyle()
    }

    // MARK: - Lista części
    private func partRow(_ p: [String: Any]) -> some View {
        let key = partKey(p)
        let status = statusMap[key]
        return VStack(alignment: .leading, spacing: 2) {
            Text("ID: \(strVal(p["id"], fallback: strVal(p["kodKreskowy"])))")
            Text(strVal(p["nazwa"]))
            Text("Ilość: \((p["magazyn_IloscSztuk"] as? NSNumber)?.intValue.description ?? "0")")
            Text("Cena: \(String((p["cena"] as? NSNumber)?.doubleValue ?? 0.0))")
            switch status {
            case .success:
                Text("Przeniesiono")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            case .failed:
                Text("Błąd przeniesienia")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(rowBackground(status), in: .rect(cornerRadius: 8))
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }

    private func rowBackground(_ status: MoveStatus?) -> Color {
        switch status {
        case .success: return Color(red: 0.80, green: 0.96, blue: 0.82) // 0xFFCCF5D2
        case .failed: return Color(red: 1.0, green: 0.88, blue: 0.88) // 0xFFFFE0E0
        default: return Color(.secondarySystemBackground)
        }
    }

    private func partKey(_ p: [String: Any]) -> String {
        (p["kodKreskowy"] as? String) ?? (p["id"] as? String) ?? ""
    }

    private func strVal(_ v: Any?, fallback: String = "") -> String {
        (v as? String) ?? fallback
    }

    // MARK: - Skan (odpowiednik DataWedge: stare pole → fetch i przejście na nowe)
    private func handleScan(_ scanned: String) {
        let cleaned = PlaceOnShelfView.filterShelf(
            scanned.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
        )
        guard !cleaned.isEmpty else { return }

        let target = focused ?? lastFocused
        if target == .old {
            oldShelf = cleaned
            fetchOld()
            lastFocused = .new
            focused = .new
        } else {
            newShelf = cleaned
            lastFocused = .new
        }
    }

    // MARK: - Logika
    private func fetchOld() {
        let code = oldShelf.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        loading = true
        error = nil
        Task {
            do {
                let list = try await PartApi.fetchShelf(
                    api: apiAddress, db: db, login: user.name, password: user.password,
                    shelfCode: code
                )
                parts = list
                statusMap = [:]
                infoMessage = "Znaleziono \(list.count) pozycji"
            } catch let e {
                // nie czyścimy części — zachowaj poprzedni widok
                error = "Błąd pobierania: \(e.localizedDescription)"
            }
            loading = false
        }
    }

    private func assignAll() {
        guard !oldShelf.trimmingCharacters(in: .whitespaces).isEmpty,
              !newShelf.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Podaj oba kody półek"
            return
        }
        guard !parts.isEmpty else {
            error = "Brak części do przeniesienia"
            return
        }
        assigning = true
        error = nil
        infoMessage = nil
        Task {
            var okCount = 0
            for p in parts {
                let key = partKey(p)
                if await assignOnePart(p, shelf: newShelf.trimmingCharacters(in: .whitespaces)) {
                    okCount += 1
                    statusMap[key] = .success
                } else {
                    statusMap[key] = .failed
                }
            }
            assigning = false
            infoMessage = "Przeniesiono \(okCount) z \(parts.count)"
        }
    }

    private func assignOnePart(_ p: [String: Any], shelf: String) async -> Bool {
        let partCode = partKey(p)
        guard !partCode.isEmpty, !shelf.isEmpty else { return false }
        do {
            let resp = try await PartApi.assignToShelf(
                api: apiAddress, db: db, login: user.name, password: user.password,
                part: partCode, shelf: shelf
            )
            let kod = (resp["kod"] as? NSNumber)?.intValue ?? -1
            let status = (resp["status"] as? String) ?? ""
            return kod == 200 && status.lowercased() == "success"
        } catch {
            return false
        }
    }
}
