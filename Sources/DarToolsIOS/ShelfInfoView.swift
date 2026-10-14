import SwiftUI

// Port ShelfInfoActivity.kt — "Informacje o półce".
// Pominięte (Android/Zebra-specyficzne): DataWedge, wewnętrzna klawiatura ekranowa,
// EditText/InputConnection, klawiatura systemowa zastąpiona natywną.
struct ShelfInfoView: View {
    let db: String
    let user: User

    private var apiAddress: String { Prefs.apiAddress }
    private var helper: String { Prefs.apilohelperApi }

    // kody półek: cyfry albo "P{kod}" (jak filterShelfCode na Androidzie)
    static func filterShelf(_ raw: String) -> String {
        String(raw.filter { $0.isNumber || $0 == "P" || $0 == "p" })
            .replacingOccurrences(of: "p", with: "P")
    }

    @State private var code = ""
    @State private var loading = false
    @State private var error: String?
    @State private var results: [[String: Any]] = []
    @State private var lastSearchedShelf = ""
    @State private var showScanner = false
    @State private var pillVisible = true
    @State private var lastScrollY: CGFloat = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // przycisk "brakuje części?" pod polem (ShelfShortage)
                    if !lastSearchedShelf.isEmpty && !loading && error == nil {
                        NavigationLink(value: AppRoute.shelfShortage(db: db, user: user, shelf: lastSearchedShelf)) {
                            Text("\(lastSearchedShelf) – brakuje części?")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .padding(.top, 4)
                    }

                    Text("Ilość elementów na półce: \(results.count)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    if let e = error {
                        Text(e).foregroundStyle(.red).padding(.vertical, 4)
                    }

                    if !results.isEmpty {
                        ForEach(Array(results.prefix(50).enumerated()), id: \.offset) { _, item in
                            let initial = shelfItemCode(item)
                            NavigationLink(value: AppRoute.partInfo(db: db, user: user, initialCode: initial)) {
                                shelfRow(item)
                            }
                            .buttonStyle(.plain)
                            .disabled(initial.isEmpty)
                            .padding(10)
                            .glassEffect(.regular, in: .rect(cornerRadius: 14))
                        }
                    }
                }
                .padding(8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }, action: { _, new in
                guard !showScanner, !inputFocused else { lastScrollY = new; return }
                let d = new - lastScrollY
                if d > 8 { pillVisible = false; lastScrollY = new }
                else if d < -8 { pillVisible = true; lastScrollY = new }
            })
        }
        .navigationTitle("Informacje o półce")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            CameraPill(showScanner: $showScanner, visible: pillVisible && !inputFocused) { scanned in
                let cleaned = ShelfInfoView.filterShelf(scanned)
                if cleaned.count >= 3 { search(cleaned) }
            }
        }
    }

    // MARK: - Pole wejściowe
    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Kod półki")
                .font(.caption)
                .padding(.leading, 4)
            HStack(spacing: 8) {
                HStack {
                    TextField("np. 123 lub P123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .padding(.leading, 8)
                        .onChange(of: code) { _, v in
                            let f = ShelfInfoView.filterShelf(v)
                            if f != v { code = f }
                        }
                        .onSubmit { search(code) }
                    if !code.isEmpty {
                        Button { code = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 6)
                    }
                }
                .frame(height: 44)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

                Button("Sprawdź") { search(code) }
                    .buttonStyle(.glassProminent)
                    .frame(height: 44)
            }
        }
        .padding(8)
    }

    // MARK: - Wiersz części
    private func shelfRow(_ item: [String: Any]) -> some View {
        ShelfRow(item: item, api: apiAddress, db: db, user: user, helper: helper)
    }

    // MARK: - Logika
    private func search(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { error = "Wprowadź kod półki"; return }
        guard !apiAddress.isEmpty else { error = "Brak adresu API"; return }
        guard !db.isEmpty else { error = "Brak wybranej bazy danych"; return }
        guard !user.name.isEmpty, !user.password.isEmpty else { error = "Brak danych użytkownika"; return }

        lastSearchedShelf = input
        inputFocused = false
        code = ""
        loading = true
        error = nil

        Task {
            do {
                results = try await PartApi.fetchShelf(api: apiAddress, db: db, login: user.name, password: user.password, shelfCode: input)
            } catch let e {
                error = "Błąd: \(e.localizedDescription)"
                results = []
            }
            loading = false
        }
    }

    // Android: kodKreskowy z fallbackiem na id — do nawigacji (NavigationLink wyżej)
}

// Odpowiednik optString("kodKreskowy", optString("id", "")) — kod części do nawigacji
func shelfItemCode(_ item: [String: Any]) -> String {
    let kod = ((item["kodKreskowy"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
    return kod.isEmpty ? ((item["id"] as? String) ?? "").trimmingCharacters(in: .whitespaces) : kod
}

// MARK: - Wiersz listy (jak ShelfListItem na Androidzie)
private struct ShelfRow: View {
    let item: [String: Any]
    let api: String
    let db: String
    let user: User
    let helper: String

    @State private var img: UIImage?
    @State private var placeDate = "Brak daty odłożenia"

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle().fill(.gray.opacity(0.35))
                if let img {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Text("Brak").foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 64)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text("ID: \(str(item["id"]).isEmpty ? str(item["kodKreskowy"]) : str(item["id"]))")
                    .font(.subheadline)
                Text(str(item["nazwa"]))
                    .font(.caption)
                Text("Ilość: \(intStr(item["magazyn_IloscSztuk"]))")
                    .font(.caption)
                Text("Cena: \(priceStr(item["cena"]))")
                    .font(.caption)
                Text(placeDate)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .task { await load() }
    }

    private func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    private func intStr(_ v: Any?) -> String {
        (v as? NSNumber)?.intValue.description ?? "0"
    }

    private func priceStr(_ v: Any?) -> String {
        // Android optDouble → np. "12.0"
        String((v as? NSNumber)?.doubleValue ?? 0.0)
    }

    private func load() async {
        let uuid = ((item["podstawoweZdjecie"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        if !uuid.isEmpty {
            if let cached = PhotoCache.shared.get(uuid) {
                img = UIImage(data: cached)
            } else if let data = await PartApi.fetchPhoto(api: api, db: db, login: user.name, password: user.password, uuid: uuid) {
                PhotoCache.shared.put(uuid, data)
                img = UIImage(data: data)
            }
        }

        // data odłożenia z apilohelper
        guard !helper.isEmpty else { return }
        let sku = shelfItemCode(item)
        guard !sku.isEmpty else { return }
        if let txt = await PartApi.partPlaceDate(helper: helper, profil: PartApi.profile(db), sku: sku)?
            .trimmingCharacters(in: .whitespaces),
           !txt.isEmpty, !txt.lowercased().contains("brak") {
            placeDate = "Data odłożenia: \(txt)"
        }
    }
}
