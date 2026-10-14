import SwiftUI

// Port PartInfoScreen.kt — "Pokaż informacje o części".
// Pominięte (Android/Zebra-specyficzne): ScanKeyDispatcher, DataWedge, EditText/InputConnection,
// wewnętrzna klawiatura (iPhone ma systemową), deep linki.
struct PartInfoView: View {
    let db: String
    let user: User
    var initialCode: String? = nil // np. ze Screen "Informacje o półce"

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var net = NetworkStatus.shared

    private var apiAddress: String { Prefs.apiAddress }
    private var helper: String { Prefs.apilohelperApi }

    // stan
    @State private var code = ""
    @State private var loading = false
    @State private var error: String?
    @State private var part: [String: Any]?
    @State private var image: UIImage?
    @State private var factoryNumber = "-"
    @State private var addDate = "Brak daty dodania"
    @State private var placeDate = "Brak daty odłożenia"
    @State private var hasDesc = false
    @State private var hasNote = false
    @State private var descText: String?
    @State private var noteText: String?
    @State private var showDescDialog = false
    @State private var showNoteDialog = false
    @State private var showNoteEditDialog = false
    @State private var editNote = ""
    @State private var isSavingNote = false
    @State private var toast: String?
    @State private var imageFailed = false

    // FAB / skaner
    @State private var showScanner = false
    @State private var showAddDialog = false
    @State private var showChoiceDialog = false
    @State private var pillVisible = true
    @State private var lastScrollY: CGFloat = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            if loading {
                ProgressView().padding(.top, 8)
            }
            if let e = error {
                Text(e).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            content
        }
        .overlay(alignment: .bottom) {
            CameraPill(showScanner: $showScanner, visible: pillVisible && !inputFocused) { searchCode($0) }
        }
        .task {
            if let c = initialCode, !c.isEmpty { code = c; search() }
        }
        .navigationTitle("Pokaż informacje o części")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if part != nil {
                    // w toolbarze iOS 26 sam daje glass — bez .glass, żeby nie było podwójnej ramki
                    Button {
                        if hasNote { showAddDialog = true } else { showChoiceDialog = true }
                    } label: {
                        Image(systemName: "plus").font(.title3.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dodaj")
                } else {
                    // jak FAB na Androidzie: bez załadowanej części otwórz listę podręczną
                    NavigationLink(value: AppRoute.quickParts(db: db, user: user)) {
                        Image(systemName: "plus").font(.title3.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Lista")
                }
            }
        }
        .alert("Opis części", isPresented: $showDescDialog) {
            Button("Zamknij", role: .cancel) {}
        } message: { Text(descText ?? "Brak opisu") }
        .alert("Notatka", isPresented: $showNoteDialog) {
            Button("Edytuj notatkę") {
                editNote = noteText ?? ""
                showNoteEditDialog = true
            }
            Button("Zamknij", role: .cancel) {}
        } message: { Text(noteText ?? "Brak notatki") }
        .alert("Edytuj notatkę", isPresented: $showNoteEditDialog) {
            TextField("Notatka", text: $editNote, axis: .vertical)
            Button("Anuluj", role: .cancel) {}
            Button("Zapisz") { saveNote() }
        }
        .alert("Wybierz akcję", isPresented: $showChoiceDialog) {
            Button("Dodaj do listy części") { showAddDialog = true }
            Button("Dodaj notatkę") {
                editNote = noteText ?? ""
                showNoteEditDialog = true
            }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Co chcesz zrobić?") }
        .alert("Dodaj do listy części", isPresented: $showAddDialog) {
            Button("Złomowanie") { addToList("złomowanie") }
            Button("Weryfikacja") { addToList("weryfikacja") }
            Button("Anuluj", role: .cancel) {}
        } message: { Text("Wybierz cel dodania:") }
        .toast($toast)
    }

    // MARK: - Pole wyszukiwania
    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ID części / kod kreskowy")
                .font(.caption)
                .padding(.leading, 4)
            HStack(spacing: 8) {
                HStack {
                    TextField("np. 123456789", text: $code)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .padding(.leading, 8)
                    if !code.isEmpty {
                        Button {
                            code = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 6)
                    }
                }
                .frame(height: 44)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                .onSubmit { search() }

                Button("Sprawdź") { search() }
                    .buttonStyle(.glassProminent)
                    .frame(height: 44)
            }
        }
        .padding(8)
    }

    // MARK: - Treść
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let p = part {
                    partCard(p)
                }
                Text("Historia:")
                    .font(.headline)
                    .padding(.top, 4)
                if let historia = (part?["historia"] as? [[String: Any]]), !historia.isEmpty {
                    ForEach(Array(historia.sorted { ($0["data"] as? String ?? "") > ($1["data"] as? String ?? "") }.enumerated()), id: \.offset) { _, h in
                        VStack(alignment: .leading, spacing: 2) {
                            if let d = h["data"] as? String, !d.isEmpty {
                                Text(PartApi.formatDateShort(d)).font(.caption)
                            }
                            if let u = h["uzytkownik"] as? String, !u.isEmpty { Text(u).font(.caption) }
                            if let o = h["opis"] as? String, !o.isEmpty { Text(o).font(.caption) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                } else if part != nil {
                    Text("Brak historii").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .scrollDismissesKeyboard(.interactively)
        // ukrywanie pigułki: scroll w dół → hide, w górę → show (jak snapshotFlow na Androidzie)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { _, new in
            guard !showScanner, !inputFocused else { lastScrollY = new; return }
            let d = new - lastScrollY
            if d > 8 { pillVisible = false; lastScrollY = new }
            else if d < -8 { pillVisible = true; lastScrollY = new }
        })
    }

    private func partCard(_ p: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // zdjęcie → galeria zdjęć części (PartPhotos)
            NavigationLink(value: AppRoute.partPhotos(db: db, user: user, partId: currentIdForPhotos(p))) {
                ZStack {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(.gray.opacity(0.35))
                        Text(imageFailed ? "Zdjęcie (błąd)" : "Zdjęcie (brak)").foregroundStyle(.secondary)
                    }
                }
                .frame(height: 140)
                .clipShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            let fields: [(String, String)] = [
                ("ID", str(p["id"], "-")),
                ("Lokalizacja", PartApi.formatLocation(str(p["lokalizacja"], ""))),
                ("Nazwa", str(p["nazwa"], "-")),
                ("Marka", str(p["marka"], "-")),
                ("Model", str(p["model"], "-")),
                ("Numer fabryczny", factoryNumber),
                ("Data dodania", addDate),
                ("Data odłożenia", placeDate),
                ("Ilość", String((p["magazyn_IloscSztuk"] as? Int) ?? 0)),
                ("Cena", String(describing: (p["cena"] as? Double) ?? (p["cena"] as? Int).map(Double.init) ?? 0.0)),
            ]
            ForEach(fields, id: \.0) { k, v in
                HStack(alignment: .top) {
                    Text(k + ":").font(.caption).frame(width: 120, alignment: .leading)
                    Text(v.isEmpty ? "-" : v).font(.subheadline)
                    Spacer()
                }
            }

            if hasDesc || hasNote {
                HStack(spacing: 8) {
                    if hasDesc {
                        Button("Pokaż opis") { showDesc() }
                            .buttonStyle(.glass)
                    }
                    if hasNote {
                        Button("Pokaż notatkę") { showNote() }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Akcje

    private func str(_ v: Any?, _ def: String) -> String {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return def
    }

    private func search() {
        // Android doSearch: tylko trim, bez filtrowania znaków
        let input = code.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { error = "Wprowadź ID lub kod kreskowy"; return }
        guard !apiAddress.isEmpty else { error = "Brak adresu API w ustawieniach"; return }
        guard !db.isEmpty else { error = "Brak wybranej bazy danych"; return }
        guard !user.name.isEmpty, !user.password.isEmpty else { error = "Brak danych użytkownika"; return }

        inputFocused = false // ukryj klawiaturę (numberPad nie ma Enter)
        code = ""
        part = nil
        image = nil
        imageFailed = false
        loading = true
        error = nil
        hasDesc = false
        hasNote = false
        descText = nil
        noteText = nil

        Task {
            do {
                let obj = try await PartApi.fetchPart(api: apiAddress, db: db, login: user.name, password: user.password, code: input)
                part = obj
                if let uuid = (obj["podstawoweZdjecie"] as? String)?.trimmingCharacters(in: .whitespaces), !uuid.isEmpty {
                    if let data = await PartApi.fetchPhoto(api: apiAddress, db: db, login: user.name, password: user.password, uuid: uuid) {
                        PhotoCache.shared.put(uuid, data)
                        image = UIImage(data: data)
                        imageFailed = image == nil
                    }
                }
                await fetchHelperExtras(obj)
            } catch {
                self.error = "Błąd pobierania danych: \(error.localizedDescription)"
                part = nil
            }
            loading = false
        }
    }

    // Numer fabryczny, daty, flagi opisu/notatki — po kolei (jak na Androidzie)
    private func fetchHelperExtras(_ p: [String: Any]) async {
        let profil = PartApi.profile(db)
        guard let kod = (p["kodKreskowy"] as? String)?.trimmingCharacters(in: .whitespaces), !kod.isEmpty else {
            factoryNumber = "-"
            addDate = "Brak daty dodania"
            return
        }
        guard !helper.isEmpty else { factoryNumber = "-"; return }

        factoryNumber = await PartApi.factoryNumber(helper: helper, profil: profil, numer: kod) ?? "-"

        if let dn = await PartApi.descAndNote(helper: helper, profil: profil, sku: kod) {
            hasDesc = (dn["maOpis"] as? Bool) ?? false
            hasNote = (dn["maNotatke"] as? Bool) ?? false
        } else {
            hasDesc = false
            hasNote = false
        }

        if let d = (await PartApi.partAddDate(helper: helper, profil: profil, sku: kod))?.trimmingCharacters(in: .whitespaces),
           !d.isEmpty, !d.lowercased().contains("brak") {
            addDate = d
        } else {
            addDate = "Brak daty dodania"
        }

        if let d = (await PartApi.partPlaceDate(helper: helper, profil: profil, sku: kod))?.trimmingCharacters(in: .whitespaces),
           !d.isEmpty, !d.lowercased().contains("brak") {
            placeDate = d
        } else {
            placeDate = "Brak daty odłożenia"
        }
    }

    private func currentKod() -> String {
        ((part?["kodKreskowy"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func showDesc() {
        let kod = currentKod()
        Task {
            if descText == nil {
                descText = await PartApi.partDesc(helper: helper, profil: PartApi.profile(db), sku: kod)
            }
            showDescDialog = true
        }
    }

    private func showNote() {
        let kod = currentKod()
        Task {
            if noteText == nil {
                noteText = await PartApi.partNote(helper: helper, profil: PartApi.profile(db), sku: kod)
            }
            showNoteDialog = true
        }
    }

    private func saveNote() {
        let kod = currentKod()
        guard !kod.isEmpty else { return }
        isSavingNote = true
        Task {
            let ok = await PartApi.updatePartNote(helper: helper, profil: PartApi.profile(db), sku: kod, note: editNote)
            isSavingNote = false
            if ok {
                noteText = editNote
                hasNote = true
                showNoteEditDialog = false
                showNoteDialog = false
            } else {
                toast = "Błąd podczas zapisu notatki"
            }
        }
    }

    private func currentId() -> String {
        let id = (part?["id"] as? String) ?? ""
        return id.isEmpty ? currentKod() : id
    }

    // Android: p[optString("id")].ifBlank { p[optString("kodKreskowy")] }
    private func currentIdForPhotos(_ p: [String: Any]) -> String {
        let id = ((p["id"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? ((p["kodKreskowy"] as? String) ?? "").trimmingCharacters(in: .whitespaces) : id
    }

    private func addToList(_ action: String) {
        let id = currentId()
        guard !id.isEmpty else { return }
        QuickParts.add(user: user.name, db: db, id: id, action: action)
        toast = "Dodano \(id) (\(action))"
    }

    // MARK: - Akcje
    private func searchCode(_ value: String) {
        code = value
        search()
    }
}

// Odpowiednik addQuickPartToPrefs — lista szybkich części (JSON per user+db)
enum QuickParts {
    private static func key(_ user: String, _ db: String) -> String {
        "quick_parts_\(user.lowercased())_\(db.lowercased())"
    }

    static func load(user: String, db: String) -> [[String: Any]] {
        let raw = UserDefaults.standard.string(forKey: key(user, db)) ?? "[]"
        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]]) ?? []
    }

    static func save(user: String, db: String, items: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: items) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8), forKey: key(user, db))
        }
    }

    static func add(user: String, db: String, id: String, action: String) {
        var arr = load(user: user, db: db)
        let item: [String: Any] = ["id": id, "action": action]
        if let idx = arr.firstIndex(where: { ($0["id"] as? String) == id }) {
            arr[idx] = item
        } else {
            arr.append(item)
        }
        save(user: user, db: db, items: arr)
    }

    // po masowym złomowaniu usuń z listy pozycje z sukcesem
    static func removeIds(user: String, db: String, ids: [String]) {
        let kept = load(user: user, db: db).filter { !ids.contains(($0["id"] as? String) ?? "") }
        save(user: user, db: db, items: kept)
    }
}
