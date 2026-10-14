import SwiftUI
import AVFoundation

// Port ManualPartSearchActivity — „Ręczne wyszukiwanie części".
// Pominięte: wewnętrzna klawiatura ekranowa; OCR przez Vision zamiast MLKit.
struct ManualPartSearchView: View {
    let db: String
    let user: User

    private var apiAddress: String { Prefs.apiAddress }

    private struct Item: Identifiable {
        let id = UUID()
        var obj: [String: Any]
        var imageData: Data?
    }

    private struct Indexed: Identifiable {
        let index: Int
        let item: Item
        var id: UUID { item.id }
    }

    @State private var parts: [Item] = []
    @State private var statuses: [String: String] = [:]

    @State private var showAdd = false
    @State private var inputId = ""
    @State private var inputQty = "1"
    @State private var loading = false
    @State private var errorText: String?

    @State private var selectedIndex: Int?
    @State private var showOptions = false
    @State private var openPartCode: String?
    @State private var showClearConfirm = false

    @State private var locationFilter = "Wszystkie"
    @State private var toast: String?

    // skaner
    @State private var showScanner = false
    @State private var useOcrMode = false
    @State private var scannedProducts: [(sku: String, qty: Int)] = []
    @State private var showScannedList = false
    @State private var showImportConfirm = false
    @State private var dbMismatch: String?
    @State private var importProgress: Int?
    @State private var importTotal: Int?
    @State private var cameraDenied = false

    var body: some View {
        VStack(spacing: 0) {
            filterCard

            if loading || errorText != nil {
                HStack(spacing: 8) {
                    if loading { ProgressView() }
                    if let e = errorText {
                        Text(e).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if parts.isEmpty {
                Spacer()
                Text("Brak pozycji na liście")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayed) { entry in
                            partCard(index: entry.index, item: entry.item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 8)
        .navigationTitle("Ręczne wyszukiwanie części")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showClearConfirm = true } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Wyczyść listę")
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toast($toast)
        .navigationDestination(isPresented: Binding(
            get: { openPartCode != nil },
            set: { if !$0 { openPartCode = nil } }
        )) {
            PartInfoView(db: db, user: user, initialCode: openPartCode ?? "")
        }
        // Dodawanie części
        .alert("Wprowadź ID części", isPresented: $showAdd) { addAlertActions }
        // Opcje części
        .alert("Opcje części", isPresented: $showOptions, presenting: selectedIndex) { idx in
            Button("Pokaż informacje o części") {
                openPartCode = infoCode(parts[idx].obj)
            }
            Button("Oznacz jako znalezione") { setStatus(idx, "found") }
            Button("Oznacz jako nieznalezione") { setStatus(idx, "not_found") }
            Button("Usuń z listy", role: .destructive) { removeAt(idx) }
            Button("Anuluj", role: .cancel) {}
        } message: { idx in
            Text("\(partKey(parts[idx].obj))\n\((parts[idx].obj["nazwa"] as? String) ?? "")")
        }
        .alert("Potwierdzenie", isPresented: $showClearConfirm) {
            Button("Tak, wyczyść", role: .destructive) {
                parts.removeAll()
                statuses.removeAll()
                locationFilter = "Wszystkie"
                save()
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Czy na pewno chcesz wyczyścić listę części?")
        }
        .alert("Błędna baza", isPresented: Binding(
            get: { dbMismatch != nil },
            set: { if !$0 { dbMismatch = nil } }
        )) {
            Button("OK", role: .cancel) { dbMismatch = nil }
        } message: {
            Text(dbMismatch ?? "")
        }
        .alert("Import z QR", isPresented: $showImportConfirm) {
            Button("Tak, wyczyść i importuj") { importProducts(clear: true) }
            Button("Dodaj do istniejących") { importProducts(clear: false) }
            Button("Anuluj", role: .cancel) { scannedProducts = [] }
        } message: {
            Text("Czy wyczyścić listę części przed importem?")
        }
        .alert("Importowanie części", isPresented: Binding(
            get: { importProgress != nil },
            set: { if !$0 { importProgress = nil; importTotal = nil } }
        )) {
            EmptyView()
        } message: {
            Text("\(importProgress ?? 0) / \(importTotal ?? 1)")
        }
        .alert("Kamera", isPresented: $cameraDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Brak uprawnień do kamery")
        }
        .sheet(isPresented: $showScannedList) { scannedListSheet }
        .onAppear(perform: load)
    }

    // MARK: - Dolny pasek (pigułka QR/OCR + dodawanie)
    @ViewBuilder private var addAlertActions: some View {
        TextField("ID / Kod", text: $inputId).keyboardType(.numberPad)
        TextField("Ilość", text: $inputQty).keyboardType(.numberPad)
        Button("OK") { addPart() }
        Button("Anuluj", role: .cancel) { inputId = ""; inputQty = "1" }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if showScanner {
                scannerPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                HStack(spacing: 12) {
                    Button { requestCamera() } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3)
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular, in: .circle)
                    }
                    .accessibilityLabel("Skanuj QR")

                    PrimaryActionBar(title: "Dodaj część", systemImage: "plus") {
                        inputId = ""
                        inputQty = "1"
                        showAdd = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.screen, value: showScanner)
    }

    private var scannerPanel: some View {
        ZStack {
            Color.black
            if useOcrMode {
                CameraOcrScanner { codes in handleOcr(codes) }
                    .allowsHitTesting(false)
            } else {
                CameraBarcodeScanner { raw in handleQr(raw) }
                    .allowsHitTesting(false)
            }

            VStack {
                HStack(spacing: 8) {
                    segment("QR", active: !useOcrMode) { useOcrMode = false }
                    segment("OCR", active: useOcrMode) { useOcrMode = true }
                    if useOcrMode && !scannedProducts.isEmpty {
                        Text("+\(scannedProducts.count)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tint)
                        Button {
                            showScanner = false
                            showScannedList = true
                        } label: {
                            Text("Gotowe")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .glassEffect(.regular, in: .capsule)

                Spacer()
            }
            .padding(12)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        // tap poza przełącznikiem zamyka podgląd (jak na Androidzie)
        .onTapGesture {
            showScanner = false
            if useOcrMode && !scannedProducts.isEmpty { showScannedList = true }
        }
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtr lokalizacji
    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filtruj po lokalizacji:")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(locationCategories, id: \.self) { cat in
                    Button("\(cat) (\(countFor(cat)))") { locationFilter = cat }
                }
            } label: {
                HStack {
                    Text(locationFilter)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
    }

    // MARK: - Karta części
    private func partCard(index: Int, item: Item) -> some View {
        let part = item.obj
        let st = statuses[partKey(part)]
        let bg: Color = st == "found" ? Color(red: 0.647, green: 0.839, blue: 0.655)
            : st == "not_found" ? Color(red: 0.937, green: 0.604, blue: 0.604)
            : Color(.secondarySystemBackground)

        return Button {
            selectedIndex = index
            showOptions = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(partKey(part))
                        .font(.body.weight(.bold))
                        .foregroundStyle(.tint)
                    Text((part["nazwa"] as? String) ?? "")
                        .font(.subheadline)
                        .lineLimit(2)
                    Text((part["lokalizacja"] as? String) ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(qty(part))")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))

                if let d = item.imageData, let img = UIImage(data: d) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 80, height: 80)
                        .overlay(Text("Brak").font(.caption2).foregroundStyle(.secondary))
                }
            }
            .padding(8)
            .foregroundStyle(.primary)
            .background(bg, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lista zeskanowanych kodów (przed importem)
    private var scannedListSheet: some View {
        NavigationStack {
            Group {
                if scannedProducts.isEmpty {
                    VStack {
                        Spacer()
                        Text("Brak zeskanowanych kodów")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(Array(scannedProducts.enumerated()), id: \.offset) { i, p in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("SKU: \(p.sku)")
                                    Text("Ilość: \(p.qty)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    scannedProducts.remove(at: i)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Zeskanowane kody (\(scannedProducts.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") {
                        scannedProducts = []
                        showScannedList = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importuj") {
                        showScannedList = false
                        showImportConfirm = true
                    }
                    .disabled(scannedProducts.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Logika
    private func partKey(_ o: [String: Any]) -> String {
        if let id = o["id"] as? String, !id.isEmpty { return id }
        return (o["kodKreskowy"] as? String) ?? ""
    }

    private func infoCode(_ o: [String: Any]) -> String {
        if let k = o["kodKreskowy"] as? String, !k.isEmpty { return k }
        return (o["id"] as? String) ?? ""
    }

    private func qty(_ o: [String: Any]) -> Int {
        if let i = o["magazyn_IloscSztuk"] as? Int { return i }
        if let s = o["magazyn_IloscSztuk"] as? String, let i = Int(s) { return i }
        return 0
    }

    private var displayed: [Indexed] {
        parts.enumerated().map { Indexed(index: $0.offset, item: $0.element) }.filter { entry in
            locationFilter == "Wszystkie" ||
            locationCategoriesFor((entry.item.obj["lokalizacja"] as? String) ?? "").contains(locationFilter)
        }
    }

    // Jak w Androidzie: kategorie „HALA ANTRESOLA\POZIOM n" itd.
    private func locationCategoriesFor(_ loc: String) -> [String] {
        let cleaned = loc.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let parts = cleaned.split(separator: "\\")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return [] }
        var result = [first]

        if first.uppercased() == "HALA ANTRESOLA" {
            let re = try! NSRegularExpression(pattern: #"POZIOM\s*(\d+)"#, options: .caseInsensitive)
            var levels = Set<Int>()
            for seg in parts {
                let r = NSRange(seg.startIndex..<seg.endIndex, in: seg)
                if let m = re.firstMatch(in: seg, range: r), let range = Range(m.range(at: 1), in: seg),
                   let n = Int(seg[range]), (0...2).contains(n) {
                    levels.insert(n)
                }
            }
            for n in levels.sorted() { result.append("\(first)\\POZIOM \(n)") }
        } else if parts.count >= 2, parts[1].uppercased().hasPrefix("POZIOM") {
            result.append("\(first)\\\(parts[1])")
        }
        return result
    }

    private var locationCategories: [String] {
        var cats = Set<String>()
        for it in parts {
            cats.formUnion(locationCategoriesFor((it.obj["lokalizacja"] as? String) ?? ""))
        }
        if cats.contains(where: { $0.uppercased().hasPrefix("HALA ANTRESOLA\\POZIOM") }) {
            cats = cats.filter { $0.uppercased() != "HALA ANTRESOLA" }
        }
        return ["Wszystkie"] + cats.sorted()
    }

    private func countFor(_ cat: String) -> Int {
        if cat == "Wszystkie" { return parts.count }
        return parts.filter {
            locationCategoriesFor(($0.obj["lokalizacja"] as? String) ?? "").contains(cat)
        }.count
    }

    // MARK: - Dodawanie / operacje na liście
    private func addPart() {
        let id = inputId.trimmingCharacters(in: .whitespaces)
        let qtyValue = Int(inputQty) ?? 1
        guard !id.isEmpty else { return }
        loading = true
        errorText = nil
        Task {
            await fetchAndAppend(codes: [(id, qtyValue)], reportLocalFallback: true)
            loading = false
            inputId = ""
            inputQty = "1"
        }
    }

    private func setStatus(_ idx: Int, _ status: String) {
        guard parts.indices.contains(idx) else { return }
        let k = partKey(parts[idx].obj)
        if !k.isEmpty {
            statuses[k] = status
            save()
        }
    }

    private func removeAt(_ idx: Int) {
        guard parts.indices.contains(idx) else { return }
        let k = partKey(parts[idx].obj)
        parts.remove(at: idx)
        if !k.isEmpty { statuses.removeValue(forKey: k) }
        save()
    }

    // MARK: - Skanowanie
    private func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    showScanner = granted
                    cameraDenied = !granted
                }
            }
        default:
            cameraDenied = true
        }
    }

    private func handleQr(_ raw: String) {
        showScanner = false
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorText = "Błąd parsowania QR"
            return
        }
        let scannedDb = (root["db"] as? String) ?? ""
        if scannedDb.lowercased() != db.lowercased() {
            dbMismatch = "Zeskanowano dla bazy: \(scannedDb) — jesteś w bazie: \(db)"
            return
        }
        var out: [(sku: String, qty: Int)] = []
        if let arr = root["products"] as? [[String: Any]] {
            for p in arr {
                let sku = (p["sku"] as? String) ?? (p["id"] as? String) ?? ""
                let qtyValue = (p["qty"] as? Int) ?? (p["quantity"] as? Int) ?? 1
                if !sku.isEmpty { out.append((sku, qtyValue)) }
            }
        }
        scannedProducts = out
        if out.isEmpty {
            errorText = "Brak produktów w QR"
        } else {
            showImportConfirm = true
        }
    }

    private func handleOcr(_ codes: [String]) {
        var added: [String] = []
        for c in codes where !scannedProducts.contains(where: { $0.sku == c }) {
            scannedProducts.append((c, 1))
            added.append(c)
        }
        if !added.isEmpty {
            toast = "Zeskanowano: \(added.joined(separator: ", ")) (\(scannedProducts.count) łącznie)"
        }
    }

    private func importProducts(clear: Bool) {
        let list = scannedProducts
        loading = true
        errorText = nil
        importTotal = list.count
        importProgress = 0
        if clear { parts.removeAll() }
        Task {
            await fetchAndAppend(codes: list, reportLocalFallback: false)
            loading = false
            showImportConfirm = false
            scannedProducts = []
            importProgress = nil
            importTotal = nil
        }
    }

    // Pobiera dane części + zdjęcie i dopisuje do listy (fallback: minimalny obiekt)
    private func fetchAndAppend(codes: [(String, Int)], reportLocalFallback: Bool) async {
        for c in codes {
            let code = c.0
            let q = c.1
            do {
                var obj = try await PartApi.fetchPart(
                    api: apiAddress, db: db,
                    login: user.name, password: user.password, code: code
                )
                obj["magazyn_IloscSztuk"] = q
                var img: Data?
                let uuid = ((obj["podstawoweZdjecie"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespaces)
                if !uuid.isEmpty {
                    img = await PartApi.fetchPhoto(
                        api: apiAddress, db: db,
                        login: user.name, password: user.password, uuid: uuid
                    )
                }
                parts.append(Item(obj: obj, imageData: img))
            } catch {
                parts.append(Item(obj: [
                    "id": code, "kodKreskowy": code, "nazwa": "",
                    "magazyn_IloscSztuk": q
                ], imageData: nil))
                if reportLocalFallback {
                    errorText = "Część dodana lokalnie (brak danych z serwera)"
                }
            }
            if importTotal != nil { importProgress = (importProgress ?? 0) + 1 }
        }
        save()
    }

    // MARK: - Trwałość (odpowiednik SharedPreferences manual_parts_list_<db>)
    private func save() {
        var arr: [[String: Any]] = []
        for it in parts {
            guard let d = try? JSONSerialization.data(withJSONObject: it.obj),
                  let str = String(data: d, encoding: .utf8) else { continue }
            arr.append([
                "part": str,
                "image": it.imageData?.base64EncodedString() ?? "",
                "status": statuses[partKey(it.obj)] ?? ""
            ])
        }
        if let d = try? JSONSerialization.data(withJSONObject: arr) {
            UserDefaults.standard.set(String(data: d, encoding: .utf8),
                                      forKey: "manual_parts_list_\(db)")
        }
    }

    private func load() {
        guard parts.isEmpty else { return }
        let raw = UserDefaults.standard.string(forKey: "manual_parts_list_\(db)") ?? "[]"
        guard let arr = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]] else { return }
        for it in arr {
            guard let ps = it["part"] as? String, !ps.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(ps.utf8)) as? [String: Any] else { continue }
            let img = (it["image"] as? String).flatMap { Data(base64Encoded: $0) }
            parts.append(Item(obj: obj, imageData: img))
            let st = (it["status"] as? String) ?? ""
            let k = partKey(obj)
            if !k.isEmpty && !st.isEmpty { statuses[k] = st }
        }
    }
}
