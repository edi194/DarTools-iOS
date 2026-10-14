import SwiftUI

enum AppRoute: Hashable {
    case partInfo(db: String, user: User, initialCode: String?)
    case partPhotos(db: String, user: User, partId: String)
    case shelfInfo(db: String, user: User)
    case scrap(db: String, user: User)
    case placeOnShelf(db: String, user: User)
    case moveShelf(db: String, user: User)
    case quickParts(db: String, user: User)
    case braki(db: String, user: User)
    case partSearch(db: String, user: User)
    case manualPartSearch(db: String, user: User)
    case shelfShortage(db: String, user: User, shelf: String)

    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        switch (lhs, rhs) {
        case let (.partInfo(d1, u1, c1), .partInfo(d2, u2, c2)): return d1 == d2 && u1.name == u2.name && c1 == c2
        case let (.partPhotos(d1, u1, p1), .partPhotos(d2, u2, p2)): return d1 == d2 && u1.name == u2.name && p1 == p2
        case let (.shelfInfo(d1, u1), .shelfInfo(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.scrap(d1, u1), .scrap(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.placeOnShelf(d1, u1), .placeOnShelf(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.moveShelf(d1, u1), .moveShelf(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.quickParts(d1, u1), .quickParts(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.braki(d1, u1), .braki(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.partSearch(d1, u1), .partSearch(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.manualPartSearch(d1, u1), .manualPartSearch(d2, u2)): return d1 == d2 && u1.name == u2.name
        case let (.shelfShortage(d1, u1, s1), .shelfShortage(d2, u2, s2)): return d1 == d2 && u1.name == u2.name && s1 == s2
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .partInfo(db, user, initialCode):
            hasher.combine(0); hasher.combine(db); hasher.combine(user.name); hasher.combine(initialCode)
        case let .partPhotos(db, user, partId):
            hasher.combine(1); hasher.combine(db); hasher.combine(user.name); hasher.combine(partId)
        case let .shelfInfo(db, user):
            hasher.combine(2); hasher.combine(db); hasher.combine(user.name)
        case let .scrap(db, user):
            hasher.combine(3); hasher.combine(db); hasher.combine(user.name)
        case let .placeOnShelf(db, user):
            hasher.combine(4); hasher.combine(db); hasher.combine(user.name)
        case let .moveShelf(db, user):
            hasher.combine(5); hasher.combine(db); hasher.combine(user.name)
        case let .quickParts(db, user):
            hasher.combine(6); hasher.combine(db); hasher.combine(user.name)
        case let .braki(db, user):
            hasher.combine(7); hasher.combine(db); hasher.combine(user.name)
        case let .partSearch(db, user):
            hasher.combine(8); hasher.combine(db); hasher.combine(user.name)
        case let .manualPartSearch(db, user):
            hasher.combine(9); hasher.combine(db); hasher.combine(user.name)
        case let .shelfShortage(db, user, shelf):
            hasher.combine(10); hasher.combine(db); hasher.combine(user.name); hasher.combine(shelf)
        }
    }
}

struct LoginView: View {
    @State private var users: [User] = []
    @State private var apiAddress = Prefs.apiAddress
    @State private var apiVersion: String?
    @State private var apiStatus: String?
    @State private var showDbDialog = false
    @State private var dbList: [String] = []
    @State private var selectedUser: User?
    @State private var loggingIn = false
    @State private var loginError: String?
    @State private var showAddDialog = false
    @State private var addLogin = ""
    @State private var addPass = ""
    @State private var loggedInDb: String?
    @State private var loggedInUser: User?
    @State private var showSettings = false
    @State private var path = NavigationPath()

    @ObservedObject private var net = NetworkStatus.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        NavigationStack(path: $path) {
            GlassEffectContainer(spacing: 12) {
                Group {
                    if let db = loggedInDb, let user = loggedInUser {
                        LoggedInScreen(
                            dbName: db,
                            user: user,
                            onLogout: {
                                withAnimation(.screen) {
                                    loggedInDb = nil
                                    loggedInUser = nil
                                    selectedUser = nil
                                    dbList = []
                                }
                            },
                            onSwitchDb: { switchDb(user: user) },
                            onOpen: { path.append($0) }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else {
                        loginBody
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .animation(.screen, value: loggedInDb)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .partInfo(db, user, initialCode):
                        PartInfoView(db: db, user: user, initialCode: initialCode)
                    case let .partPhotos(db, user, partId):
                        PartPhotosView(db: db, user: user, partId: partId)
                    case let .shelfInfo(db, user):
                        ShelfInfoView(db: db, user: user)
                    case let .scrap(db, user):
                        ScrapView(db: db, user: user)
                    case let .placeOnShelf(db, user):
                        PlaceOnShelfView(db: db, user: user)
                    case let .moveShelf(db, user):
                        MoveShelfView(db: db, user: user)
                    case let .quickParts(db, user):
                        QuickPartsView(db: db, user: user)
                    case let .braki(db, user):
                        BrakiView(db: db, user: user)
                    case let .partSearch(db, user):
                        PartSearchView(db: db, user: user)
                    case let .manualPartSearch(db, user):
                        ManualPartSearchView(db: db, user: user)
                    case let .shelfShortage(db, user, shelf):
                        ShelfShortageView(db: db, user: user, shelf: shelf)
                    }
                }
            }
        }
        .overlay { if loggingIn { ProgressOverlay().transition(.opacity) } }
        .animation(.quick, value: loggingIn)
        .alert("Wybierz bazę danych", isPresented: $showDbDialog) {
            ForEach(displayDbList, id: \.self) { db in
                Button(db) {
                    if let user = selectedUser ?? loggedInUser {
                        performLogin(user: user, chosen: db)
                    } else {
                        loginError = "Brak wybranego użytkownika"
                    }
                }
            }
            Button("Anuluj", role: .cancel) {}
        }
        .alert("Błąd", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(loginError ?? "") }
        .sheet(isPresented: $showSettings, onDismiss: { apiAddress = Prefs.apiAddress }) {
            SettingsView()
        }
        .task(id: apiAddress) {
            apiVersion = nil
            apiStatus = nil
            guard !apiAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            apiStatus = "Sprawdzam..."
            do {
                apiVersion = try await Api.fetchApiVersion(apiAddress)
                apiStatus = nil
            } catch {
                apiStatus = "Błąd: \(error.localizedDescription)"
            }
        }
        .onAppear {
            users = Prefs.loadUsers().sorted { $0.name.lowercased() < $1.name.lowercased() }
            apiAddress = Prefs.apiAddress
        }
    }

    // MARK: - Ekran logowania
    private var loginBody: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)
                        .glassEffect(in: .circle)
                    Text("Dodaj użytkownika").font(.headline)
                    Spacer()
                    Button("Dodaj") { showAddDialog = true }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                }
            }
            Section {
                ForEach(users) { user in
                    HStack(spacing: 12) {
                        AvatarCircle(name: user.name)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name).font(.headline)
                            if user.allowedDbs.isEmpty {
                                Text("Brak znanych baz")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(user.allowedDbs.joined(separator: ", "))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        Spacer()
                        Button("Zaloguj") {
                            selectedUser = user
                            loginTapped(user)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                        .disabled(user.allowedDbs.isEmpty && !net.isOnline)
                    }
                }
                .onDelete { idx in
                    withAnimation(.screen) {
                        users.remove(atOffsets: idx)
                        Prefs.saveUsers(users)
                    }
                }
            } header: {
                Text("Użytkownicy")
            }
        }
        .navigationTitle("DarTools Mobile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Ustawienia")
            }
        }
        .safeAreaInset(edge: .bottom) { footer }
        .alert("Dodaj użytkownika", isPresented: $showAddDialog) {
            TextField("Login", text: $addLogin)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Hasło", text: $addPass)
            Button("Anuluj", role: .cancel) {
                addLogin = ""
                addPass = ""
            }
            Button("Zapisz") {
                addUser(addLogin, addPass)
                addLogin = ""
                addPass = ""
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Wersja aplikacji: \(appVersion)")
            if let v = apiVersion {
                Text("Wersja API: \(v)")
            } else if let s = apiStatus {
                Text(s).foregroundStyle(.orange)
            }
            if !net.isOnline {
                Text("Brak połączenia z internetem").foregroundStyle(.red)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(in: .rect(cornerRadius: 16))
        .padding(.bottom, 8)
    }

    // MARK: - Logika (odpowiednik LoginScreen z MainActivity)
    private var displayDbList: [String] {
        guard let userCtx = selectedUser ?? loggedInUser else { return dbList }
        let canonical = users.first { $0.name.lowercased() == userCtx.name.lowercased() }
        return canonical?.allowedDbs ?? userCtx.allowedDbs
    }

    private func addUser(_ name: String, _ pass: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        withAnimation(.screen) {
            if let idx = users.firstIndex(where: { $0.name.lowercased() == trimmed.lowercased() }) {
                users[idx] = User(name: trimmed, password: pass)
            } else {
                users.append(User(name: trimmed, password: pass))
            }
            users.sort { $0.name.lowercased() < $1.name.lowercased() }
            Prefs.saveUsers(users)
        }
    }

    private func loginTapped(_ user: User) {
        guard !apiAddress.trimmingCharacters(in: .whitespaces).isEmpty else {
            loginError = "Brak adresu API w ustawieniach"
            return
        }
        if let stored = users.first(where: { $0.name.lowercased() == user.name.lowercased() }),
           !stored.allowedDbs.isEmpty {
            dbList = stored.allowedDbs
            showDbDialog = true
        } else if !net.isOnline {
            loginError = "Brak połączenia z internetem – nie można pobrać listy baz"
        } else {
            loggingIn = true
            Task {
                let allowed = await Api.discoverAllowedDbs(apiAddress, user: user)
                var updated = user
                updated.allowedDbs = allowed
                if let idx = users.firstIndex(where: { $0.name.lowercased() == user.name.lowercased() }) {
                    users[idx] = updated
                } else {
                    users.append(updated)
                }
                selectedUser = updated
                Prefs.saveUsers(users)
                dbList = allowed
                showDbDialog = true
                loggingIn = false
            }
        }
    }

    private func switchDb(user: User) {
        guard !apiAddress.trimmingCharacters(in: .whitespaces).isEmpty else {
            loginError = "Brak adresu API w ustawieniach"
            return
        }
        if let stored = users.first(where: { $0.name.lowercased() == user.name.lowercased() }),
           !stored.allowedDbs.isEmpty {
            dbList = stored.allowedDbs
            showDbDialog = true
        } else if !net.isOnline {
            loginError = "Brak połączenia z internetem – nie można pobrać listy baz"
        } else {
            loggingIn = true
            Task {
                let allowed = await Api.discoverAllowedDbs(apiAddress, user: user)
                var updated = user
                updated.allowedDbs = allowed
                if let idx = users.firstIndex(where: { $0.name.lowercased() == user.name.lowercased() }) {
                    users[idx] = updated
                }
                selectedUser = updated
                Prefs.saveUsers(users)
                dbList = allowed
                showDbDialog = true
                loggingIn = false
            }
        }
    }

    private func performLogin(user: User, chosen: String) {
        withAnimation(.quick) { loggingIn = true }
        Task {
            do {
                let ok: Bool
                if net.isOnline {
                    ok = try await Api.loginUser(apiAddress, login: user.name, password: user.password, db: chosen)
                } else {
                    ok = user.allowedDbs.contains(chosen)
                }
                if ok {
                    // dopisz bazę do dozwolonych
                    if let idx = users.firstIndex(where: { $0.name.lowercased() == user.name.lowercased() }) {
                        if !users[idx].allowedDbs.contains(chosen) {
                            users[idx].allowedDbs.append(chosen)
                        }
                    } else {
                        users.append(User(name: user.name, password: user.password, allowedDbs: [chosen]))
                    }
                    Prefs.saveUsers(users)
                    withAnimation(.screen) {
                        loggedInDb = chosen
                        loggedInUser = user
                    }
                } else if !net.isOnline {
                    loginError = "Brak połączenia z internetem – logowanie offline możliwe tylko do wcześniej zweryfikowanej bazy"
                } else {
                    loginError = "Błędny login lub hasło"
                }
            } catch {
                loginError = "Błąd logowania: \(error.localizedDescription)"
            }
            loggingIn = false
        }
    }
}

// MARK: - Dialogi

struct AvatarCircle: View {
    let name: String

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.accentColor.gradient))
    }
}

struct ProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Proszę czekać...").font(.callout)
            }
            .padding(24)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
    }
}
