import SwiftUI

// Port ScrapActivity.kt — "Złomowanie".
// Pominięte: DataWedge, wewnętrzna klawiatura (systemowa numberPad), klawisz Pomusz
// z drawable (zastąpiony symbolem SF).
struct ScrapView: View {
    let db: String
    let user: User

    @ObservedObject private var net = NetworkStatus.shared
    @Environment(\.dismiss) private var dismiss

    private var apiAddress: String { Prefs.apiAddress }
    private var helper: String { Prefs.apilohelperApi }

    private var pendingKey: String { "pending_scrap_\(user.name.lowercased())_\(db.lowercased())" }

    // stan
    @State private var code = ""
    @State private var loading = false
    @State private var message: String?
    @State private var error: String?
    @State private var helperLoading = false
    @State private var askAddToQuick: String?
    @State private var showAddDialog = false
    @State private var showScanner = false
    @State private var toast: String?
    @FocusState private var inputFocused: Bool

    // kolejka offline
    @State private var pending: [String] = []
    @State private var showPendingDialog = false
    @State private var syncingPending = false
    @State private var syncError: String?

    var body: some View {
        VStack(spacing: 0) {
            inputRow

            if !net.isOnline {
                Text("Brak połączenia – tryb offline")
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.15), in: .capsule)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            if loading {
                ProgressView().padding(.top, 8)
            }

            if let m = message {
                Text(m)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            if let e = error {
                errorBlock(e)
            }

            Spacer()
        }
        .navigationTitle("Złomowanie")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            CameraPill(showScanner: $showScanner, visible: !inputFocused) { scanned in
                // jak na Androidzie: skan tylko wpisuje kod, złomowanie przyciskiem "Złomuj"
                code = scanned.filter { $0.isNumber }
                error = nil
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
        .alert("Nie udało się złomować", isPresented: $showAddDialog) {
            Button("Tak") {
                if let id = askAddToQuick {
                    QuickParts.add(user: user.name, db: db, id: id, action: "złomowanie")
                }
                askAddToQuick = nil
            }
            Button("Nie", role: .cancel) {}
        } message: {
            Text("Czy dodać część \(askAddToQuick ?? "") do podręcznej listy (złomowanie)?")
        }
        .task {
            pending = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        }
    }

    // MARK: - Pole wejściowe
    private var inputRow: some View {
        HStack(spacing: 8) {
            HStack {
                TextField("Kod części", text: $code)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .padding(.leading, 8)
                    .onChange(of: code) { _, v in
                        error = nil
                        let f = v.filter { $0.isNumber }
                        if f != v { code = f }
                    }
                if !code.isEmpty {
                    Button { code = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 6)
                }
            }
            .frame(height: 40)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            Button("Złomuj") { doScrap() }
                .buttonStyle(.glassProminent)
                .frame(width: 96, height: 40)
        }
        .padding(12)
    }

    // MARK: - Blok błędu z akcjami (Pomusz / dodaj do listy)
    private func errorBlock(_ e: String) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(e)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)

            if askAddToQuick != nil {
                HStack(spacing: 8) {
                    if !helper.isEmpty {
                        Button {
                            runHelper()
                        } label: {
                            if helperLoading {
                                ProgressView().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "lifebuoy")
                                    .font(.title2)
                                    .frame(width: 60, height: 60)
                            }
                        }
                        .frame(width: 96, height: 96)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                        .disabled(helperLoading)
                    }

                    Button("Dodaj do listy części") { showAddDialog = true }
                        .buttonStyle(.glass)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Kolejka offline (sheet)
    private var pendingSheet: some View {
        NavigationStack {
            List {
                if let se = syncError {
                    Text(se).font(.caption).foregroundStyle(.red)
                }
                if !net.isOnline {
                    Text("Brak internetu – złomowanie możliwe po powrocie połączenia.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(pending.enumerated()), id: \.offset) { idx, id in
                    HStack {
                        Text("Część: \(id)")
                        Spacer()
                        Button {
                            pending.remove(at: idx)
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
                Button {
                    syncPending()
                } label: {
                    HStack {
                        if syncingPending {
                            ProgressView().controlSize(.small)
                        }
                        Text("Złomuj wszystko")
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

    // MARK: - Logika
    private func persistPending() {
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }

    private func doScrap() {
        let c = code.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { error = "Wprowadź kod części"; return }
        guard !apiAddress.isEmpty, !db.isEmpty, !user.name.isEmpty, !user.password.isEmpty else {
            error = "Brak konfiguracji"
            return
        }

        inputFocused = false

        // offline: do kolejki per user+db, na później
        if !net.isOnline {
            pending.append(c)
            persistPending()
            error = nil
            message = nil
            toast = "Offline – dodano do kolejki złomowania (\(pending.count))"
            code = ""
            return
        }

        loading = true
        error = nil
        message = nil

        Task {
            do {
                let resp = try await PartApi.scrap(api: apiAddress, db: db, login: user.name, password: user.password, code: c)
                let kod = (resp["kod"] as? NSNumber)?.intValue ?? -1
                let kom = (resp["komunikat"] as? String) ?? ""
                if (200...299).contains(kod) {
                    message = kom.isEmpty ? "Zezłomowano część" : kom
                } else {
                    error = kom.isEmpty ? "Błąd: \(kod)" : kom
                    askAddToQuick = c
                }
            } catch let e {
                error = e.localizedDescription
                askAddToQuick = c
            }
            loading = false
            code = ""
        }
    }

    private func runHelper() {
        guard let id = askAddToQuick else { return }
        helperLoading = true
        Task {
            do {
                let resp = try await PartApi.scrapHelper(helper: helper, db: db, login: user.name, password: user.password, id: id)
                var displayed = ""
                let raw = (((resp["scrapResult"] as? String) ?? "").trimmingCharacters(in: .whitespaces))
                if !raw.isEmpty {
                    if let data = raw.data(using: .utf8),
                       let inner = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let innerKom = inner["komunikat"] as? String, !innerKom.isEmpty {
                        displayed = innerKom
                    } else {
                        displayed = raw
                    }
                } else if let kom = resp["komunikat"] as? String {
                    displayed = kom
                }

                if displayed.contains("Zezłomowano część") {
                    message = displayed
                    askAddToQuick = nil
                    error = nil
                } else {
                    error = displayed.isEmpty ? "Brak informacji z helpera" : displayed
                }
            } catch let e {
                error = e.localizedDescription
            }
            helperLoading = false
        }
    }

    private func syncPending() {
        syncingPending = true
        syncError = nil
        Task {
            var firstErr: String?
            var synced = 0
            for id in pending {
                do {
                    let resp = try await PartApi.scrap(api: apiAddress, db: db, login: user.name, password: user.password, code: id)
                    let kod = (resp["kod"] as? NSNumber)?.intValue ?? -1
                    if (200...299).contains(kod) {
                        pending.removeAll { $0 == id }
                        synced += 1
                    } else if firstErr == nil {
                        let kom = (resp["komunikat"] as? String) ?? ""
                        firstErr = kom.isEmpty ? "Błąd (\(kod)): część \(id)" : kom
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
}
