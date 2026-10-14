import SwiftUI
import CryptoKit

// Port PlaceOnShelfActivity.kt — "Odłóż na półkę" (przypisz półkę).
// Pominięte: DataWedge, wewnętrzna klawiatura (systemowa).
struct PlaceOnShelfView: View {
    let db: String
    let user: User

    @ObservedObject private var net = NetworkStatus.shared

    private var apiAddress: String { Prefs.apiAddress }

    enum Field: Hashable { case shelf, part }

    // klucze preferencji per instancja (SHA-1 z api+db+user, jak na Androidzie)
    private var suffix: String {
        let input = "\(apiAddress)\n\(db)\n\(user.name)"
        return Insecure.SHA1.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    private var rememberKey: String { "remember_shelf_\(suffix)" }
    private var rememberedShelfKey: String { "remembered_shelf_id_\(suffix)" }
    private var pendingKey: String { "pending_shelf_assignments_\(user.name.lowercased())_\(db.lowercased())" }

    // stan
    @State private var shelfId = ""
    @State private var partId = ""
    @State private var rememberShelf = false
    @State private var message: String?
    @State private var error: String?
    @State private var isProcessing = false
    @State private var partInfo: [String: Any]?
    @State private var confirmExisting: String?
    @State private var lastFocused: Field = .shelf
    @State private var showScanner = false
    @State private var toast: String?
    @FocusState private var focused: Field?

    // kolejka offline
    @State private var pending: [PendingAssign] = []
    @State private var showPendingDialog = false
    @State private var syncingPending = false
    @State private var syncError: String?

    struct PendingAssign: Codable, Identifiable {
        var id: String { "\(partId)|\(shelfId)" }
        let partId: String
        let shelfId: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ID półki
            fieldLabel("ID półki")
            shelfField
            fieldLabel("ID części")
            partField

            if let p = partInfo {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nazwa: \((p["nazwa"] as? String) ?? "-")")
                    Text("Ilość: \((p["magazyn_IloscSztuk"] as? NSNumber)?.intValue.description ?? "0")")
                }
                .font(.subheadline)
                .padding(.horizontal, 4)
            }

            if let m = message {
                Text(m).foregroundStyle(.tint).font(.subheadline)
            }
            if let e = error {
                Text(e).foregroundStyle(.red).font(.subheadline)
            }

            Button {
                doPlace()
            } label: {
                HStack {
                    Text("Odłóż")
                    if isProcessing { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(isProcessing)

            Toggle(isOn: $rememberShelf) {
                Text("Zapamiętaj półkę")
            }
            .onChange(of: rememberShelf) { _, checked in
                savePrefs()
                if checked {
                    if !shelfId.trimmingCharacters(in: .whitespaces).isEmpty {
                        focused = .part
                        lastFocused = .part
                    } else {
                        focused = .shelf
                        lastFocused = .shelf
                    }
                } else {
                    UserDefaults.standard.removeObject(forKey: rememberedShelfKey)
                    shelfId = ""
                    focused = .shelf
                    lastFocused = .shelf
                }
            }

            if !net.isOnline {
                Text("Brak połączenia – tryb offline")
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.15), in: .capsule)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .navigationTitle("Odłóż na półkę")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focused) { _, f in if let f { lastFocused = f } }
        .overlay(alignment: .bottom) {
            CameraPill(showScanner: $showScanner, visible: focused == nil) { scanned in
                handleScan(scanned)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !pending.isEmpty {
                Button {
                    syncError = nil
                    showPendingDialog = true
                } label: {
                    Text("\(pending.count)")
                        .font(.headline)
                        .padding(10)
                        .background(net.isOnline ? Color.orange : Color.secondary.opacity(0.4), in: .circle)
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 24)
                .accessibilityLabel("Kolejka offline")
            }
        }
        .toast($toast)
        .sheet(isPresented: $showPendingDialog) { pendingSheet }
        .alert("Potwierdzenie przypisania", isPresented: Binding(
            get: { confirmExisting != nil },
            set: { if !$0 { confirmExisting = nil } }
        )) {
            Button("Tak") {
                if let loc = confirmExisting { _ = loc }
                confirmExisting = nil
                proceedAssign()
            }
            Button("Nie", role: .cancel) { confirmExisting = nil }
        } message: {
            Text("Część została wcześniej przypisana do lokalizacji: \(confirmExisting ?? "")\n\nCzy na pewno chcesz kontynuować?")
        }
        .task {
            loadPrefs()
        }
    }

    // MARK: - Pola
    private func fieldLabel(_ t: String) -> some View {
        Text(t).font(.caption).padding(.leading, 4)
    }

    private var shelfField: some View {
        HStack {
            TextField("ID półki", text: $shelfId)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .focused($focused, equals: .shelf)
                .onChange(of: shelfId) { _, v in
                    let f = PlaceOnShelfView.filterShelf(v)
                    if f != v { shelfId = f }
                }
                .onSubmit { moveFromShelfToPart() }
            if !shelfId.isEmpty {
                Button { shelfId = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .inputFieldStyle()
    }

    private var partField: some View {
        HStack {
            TextField("ID części", text: $partId)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .focused($focused, equals: .part)
                .onChange(of: partId) { _, v in
                    let f = v.filter { $0.isNumber }
                    if f != v { partId = f }
                }
                .onSubmit { fetchPartInfo(partId) }
            if !partId.isEmpty {
                Button { partId = ""; partInfo = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .inputFieldStyle()
    }

    // MARK: - Preferencje
    private func loadPrefs() {
        let d = UserDefaults.standard
        shelfId = d.string(forKey: rememberedShelfKey) ?? ""
        rememberShelf = d.bool(forKey: rememberKey)
        if rememberShelf, !shelfId.trimmingCharacters(in: .whitespaces).isEmpty {
            lastFocused = .part
        } else {
            lastFocused = .shelf
        }
        pending = (try? JSONDecoder().decode([PendingAssign].self, from: Data(d.data(forKey: pendingKey) ?? Data()))) ?? []
    }

    private func savePrefs() {
        let d = UserDefaults.standard
        d.set(rememberShelf, forKey: rememberKey)
        if rememberShelf {
            d.set(shelfId.trimmingCharacters(in: .whitespaces), forKey: rememberedShelfKey)
        } else {
            d.removeObject(forKey: rememberedShelfKey)
        }
    }

    // po akcji: czyść pole zależnie od trybu (jak clearAfterAction)
    private func clearAfterAction() {
        if rememberShelf {
            partId = ""
            partInfo = nil
            focused = .part
            lastFocused = .part
        } else {
            shelfId = ""
            partId = ""
            partInfo = nil
            focused = .shelf
            lastFocused = .shelf
        }
    }

    // MARK: - Skan / Enter
    private func handleScan(_ scanned: String) {
        let cleaned = scanned.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard !cleaned.isEmpty else { return }

        if lastFocused == .shelf {
            shelfId = PlaceOnShelfView.filterShelf(cleaned)
            if rememberShelf { savePrefs() }
            focused = .part
            lastFocused = .part
        } else {
            partId = cleaned.filter { $0.isNumber }
            partInfo = nil
            fetchPartInfo(partId)
            lastFocused = .part
        }
    }

    private func moveFromShelfToPart() {
        let cleaned = PlaceOnShelfView.filterShelf(shelfId)
        guard !cleaned.isEmpty else { return }
        shelfId = cleaned
        if rememberShelf { savePrefs() }
        focused = .part
        lastFocused = .part
    }

    private func fetchPartInfo(_ sku: String) {
        let s = sku.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, net.isOnline else { return }
        Task {
            do {
                partInfo = try await PartApi.fetchPart(api: apiAddress, db: db, login: user.name, password: user.password, code: s)
                message = "Pobrano dane części"
            } catch let e {
                partInfo = nil
                error = "Błąd pobierania informacji o części: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Logika przypisania
    private func doPlace() {
        error = nil
        focused = nil

        let shelf = shelfId.trimmingCharacters(in: .whitespaces)
        let part = partId.trimmingCharacters(in: .whitespaces)
        guard !shelf.isEmpty else { error = "Podaj ID półki"; return }
        guard !part.isEmpty else { error = "Podaj ID części"; return }
        guard !apiAddress.isEmpty, !db.isEmpty, !user.name.isEmpty, !user.password.isEmpty else {
            error = "Brak konfiguracji"
            return
        }

        // offline → kolejka
        if !net.isOnline {
            pending.append(PendingAssign(partId: part, shelfId: shelf))
            persistPending()
            message = nil
            syncError = nil
            partInfo = nil
            clearAfterAction()
            toast = "Offline – dodano do kolejki (\(pending.count))"
            return
        }

        message = "Wysyłanie..."
        isProcessing = true
        Task {
            do {
                let obj = try await PartApi.fetchPart(api: apiAddress, db: db, login: user.name, password: user.password, code: part)
                let loc = ((obj["lokalizacja"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
                isProcessing = false
                let unassigned = loc.isEmpty || loc.lowercased() == "<nieprzypisano lokalizacji>"
                if unassigned {
                    proceedAssign()
                } else {
                    confirmExisting = loc // pytanie o potwierdzenie
                }
            } catch let e {
                isProcessing = false
                message = nil
                error = e.localizedDescription
                toast = "Błąd pobierania danych części: \(e.localizedDescription)"
            }
        }
    }

    private func proceedAssign() {
        isProcessing = true
        message = "Wysyłanie przypisania..."
        error = nil
        Task {
            do {
                let resp = try await PartApi.assignToShelf(
                    api: apiAddress, db: db, login: user.name, password: user.password,
                    part: partId.trimmingCharacters(in: .whitespaces),
                    shelf: shelfId.trimmingCharacters(in: .whitespaces)
                )
                let kod = (resp["kod"] as? NSNumber)?.intValue ?? -1
                let status = (resp["status"] as? String) ?? ""
                let kom = (resp["komunikat"] as? String) ?? ""
                if kod == 200, status.lowercased() == "success" {
                    message = kom.isEmpty ? "Przypisano część do półki" : kom
                    savePrefs()
                    clearAfterAction()
                    partInfo = nil
                } else {
                    message = nil
                    error = kom.isEmpty ? "Błąd przypisania: \(kod)" : kom
                }
            } catch let e {
                message = nil
                error = e.localizedDescription
                toast = "Błąd przypisania: \(e.localizedDescription)"
            }
            isProcessing = false
        }
    }

    // MARK: - Kolejka offline
    private func persistPending() {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    private var pendingSheet: some View {
        NavigationStack {
            List {
                if let se = syncError {
                    Text(se).font(.caption).foregroundStyle(.red)
                }
                if !net.isOnline {
                    Text("Brak internetu – przypisanie możliwe po powrocie połączenia.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(pending) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Część: \(item.partId)")
                            Text("Półka: \(item.shelfId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            pending.removeAll { $0.id == item.id }
                            persistPending()
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .disabled(syncingPending)
                    }
                }
            }
            .navigationTitle("Kolejka offline (\(pending.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { showPendingDialog = false }
                        .disabled(syncingPending)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { syncPending() } label: {
                    HStack {
                        if syncingPending { ProgressView().controlSize(.small) }
                        Text("Przypisz wszystko")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .disabled(!net.isOnline || pending.isEmpty || syncingPending)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .interactiveDismissDisabled(syncingPending)
        }
        .presentationDetents([.medium, .large])
    }

    private func syncPending() {
        syncingPending = true
        syncError = nil
        Task {
            var firstErr: String?
            var synced = 0
            for item in pending {
                do {
                    let resp = try await PartApi.assignToShelf(
                        api: apiAddress, db: db, login: user.name, password: user.password,
                        part: item.partId, shelf: item.shelfId
                    )
                    let kod = (resp["kod"] as? NSNumber)?.intValue ?? ((resp["_httpCode"] as? NSNumber)?.intValue ?? -1)
                    let status = (resp["status"] as? String) ?? ""
                    if kod == 200, status.lowercased() == "success" {
                        pending.removeAll { $0.id == item.id }
                        synced += 1
                    } else if firstErr == nil {
                        let kom = (resp["komunikat"] as? String) ?? ""
                        firstErr = kom.isEmpty ? "Błąd przypisania (\(kod)): część \(item.partId)" : kom
                    }
                } catch let e {
                    if firstErr == nil { firstErr = "Błąd połączenia: \(e.localizedDescription)" }
                }
            }
            persistPending()
            syncingPending = false
            if let f = firstErr {
                syncError = "\(f) (zsynchronizowano \(synced))"
            } else {
                showPendingDialog = false
            }
        }
    }

    static func filterShelf(_ raw: String) -> String {
        String(raw.filter { $0.isNumber || $0 == "P" || $0 == "p" })
            .replacingOccurrences(of: "p", with: "P")
    }
}

extension View {
    func inputFieldStyle() -> some View {
        frame(height: 44)
            .padding(.horizontal, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
