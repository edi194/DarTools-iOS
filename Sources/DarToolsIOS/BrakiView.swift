import SwiftUI

// Port BrakiActivity.kt — "Braki towaru".
// Auto-odświeżanie: co 5 minut, z powiadomieniami systemowymi (jak na Androidzie).
struct BrakiView: View {
    let db: String
    let user: User

    @ObservedObject private var net = NetworkStatus.shared

    private var apiAddress: String { Prefs.apiAddress }
    private var helper: String { Prefs.apilohelperApi }

    struct BrakiItem: Identifiable {
        let id = UUID()
        let orderNumber: String
        let sku: String
        let orderQuantity: Int
        let platformName: String
        let source: String // "apilo" / "baselinker"
        var notatka = ""
        var nazwa = ""
        var photoUuid = ""
        var lokalizacja = ""
    }

    @State private var items: [BrakiItem] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var autoRefresh = Prefs.autoRefreshBraki
    @State private var toast: String?

    // dialog notatki
    @State private var noteTarget: BrakiItem?
    @State private var noteText = ""
    @State private var showNoteDialog = false
    // nawigacja do informacji o części (tap w SKU)
    @State private var openPart: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && items.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                if let e = error {
                    Text(e)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(groupedByPlatform, id: \.0) { platform, orders in
                            platformHeader(platform, total: orders.reduce(0) { $0 + $1.1.count })
                            ForEach(orders, id: \.0) { orderNumber, entries in
                                orderCard(orderNumber: orderNumber, entries: entries)
                            }
                        }
                        Color.clear.frame(height: 48)
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .navigationTitle("Braki towaru")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(db) | Łącznie: \(items.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryActionBar(
                title: "Pobierz braki",
                systemImage: "arrow.down.circle.fill",
                isLoading: isLoading,
                disabled: isLoading
            ) { fetchAll() }
            .padding(.horizontal, 16)
        }
        .toast($toast)
        .navigationDestination(isPresented: Binding(
            get: { openPart != nil },
            set: { if !$0 { openPart = nil } }
        )) {
            PartInfoView(db: db, user: user, initialCode: openPart ?? "")
        }
        .alert("Notatka wewnętrzna", isPresented: $showNoteDialog) {
            TextField("Treść notatki", text: $noteText, axis: .vertical)
            Button("OK") { saveNote() }
            Button("Anuluj", role: .cancel) {}
        }
        .task(id: autoRefresh) {
            guard autoRefresh else { return }
            guard !apiAddress.isEmpty, !db.isEmpty, !user.name.isEmpty, !user.password.isEmpty else {
                error = "Auto-refresh włączony, ale brak aktywnego profilu lub danych logowania"
                return
            }
            // co 5 min: odśwież listę + powiadomienie, gdy są braki (jak na Androidzie).
            // Powiadomienie tylko przy zmianie liczby, żeby nie spamować co 5 minut.
            var lastNotified: (apilo: Int, bl: Int)?
            while !Task.isCancelled && autoRefresh {
                await autoFetch()
                if let c = await BrakiAutoCheck.check(helper: helper, db: db),
                   (c.apilo > 0 || c.bl > 0), c.apilo != lastNotified?.apilo || c.bl != lastNotified?.bl {
                    Notif.braki(db: db, apiloOrders: c.apilo, blOrders: c.bl)
                    lastNotified = c
                }
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            }
        }
    }

    // MARK: - Grupowanie (platforma → zamówienie)
    private var groupedByPlatform: [(String, [(String, [BrakiItem])])] {
        let platforms = Set(items.map { $0.platformName.isEmpty ? "Inne" : $0.platformName })
        return platforms.sorted().map { platform in
            let platItems = items.filter { ($0.platformName.isEmpty ? "Inne" : $0.platformName) == platform }
            var order: [String] = []
            var buckets: [String: [BrakiItem]] = [:]
            for it in platItems {
                if buckets[it.orderNumber] == nil { order.append(it.orderNumber) }
                buckets[it.orderNumber, default: []].append(it)
            }
            return (platform, order.map { ($0, buckets[$0] ?? []) })
        }
    }

    // MARK: - Widok
    private func platformHeader(_ platform: String, total: Int) -> some View {
        HStack {
            Rectangle().frame(height: 1)
            Text(" \(platform) (\(total)) ")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func orderCard(orderNumber: String, entries: [BrakiItem]) -> some View {
        let source = entries.first?.source ?? ""
        let notatka = (entries.first?.notatka ?? "").trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 6) {
            Text(source == "baselinker" ? "BL - \(orderNumber)" : orderNumber)
                .font(.body.weight(.bold))

            ForEach(entries) { entry in
                entryRow(entry)
                if entry.id != entries.last?.id {
                    Divider()
                }
            }

            if !notatka.isEmpty {
                Text("Notatka: \(notatka)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(red: 1.0, green: 0.65, blue: 0.15), in: .rect(cornerRadius: 6))
            }
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func entryRow(_ entry: BrakiItem) -> some View {
        HStack(spacing: 8) {
            BrakiThumb(api: apiAddress, db: db, user: user, uuid: entry.photoUuid)
                .frame(width: 72, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("SKU: \(entry.sku)")
                    .font(.caption)
                if !entry.nazwa.isEmpty {
                    Text(entry.nazwa)
                        .font(.caption)
                        .lineLimit(2)
                }
                Text("Ilość: \(entry.orderQuantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let loc = PartApi.formatLocation(entry.lokalizacja)
                if !loc.isEmpty {
                    Text(loc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .onTapGesture {
            guard !entry.sku.isEmpty else { return }
            openPart = entry.sku
        }
        .contextMenu {
            Button("Notatka wewnętrzna") {
                noteTarget = entry
                noteText = entry.notatka
                showNoteDialog = true
            }
            if entry.source == "apilo" {
                Button("Oznacz jako znaleziona") { markFound(entry) }
            }
        }
    }

    // MARK: - Logika
    private func fetchAll() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        Task {
            do {
                items = try await fetchEnriched()
            } catch let e {
                self.error = e.localizedDescription
                items = []
            }
            isLoading = false
        }
    }

    private func autoFetch() async {
        do {
            items = try await fetchEnriched()
        } catch { /* w pętli auto-refresh błędy ignorowane jak na Androidzie */ }
    }

    private func fetchEnriched() async throws -> [BrakiItem] {
        let profile = PartApi.profileStripped(db)
        var merged: [BrakiItem] = []
        merged += try await fetchApilo(profile: profile)
        merged += try await fetchBaselinker(profile: profile)
        return await enrich(merged)
    }

    private func fetchApilo(profile: String) async throws -> [BrakiItem] {
        guard !helper.isEmpty else { return [] }
        let orders = try await OrdersApi.apiloOrders(helper: helper, profile: profile)
        var out: [BrakiItem] = []
        for order in orders {
            let orderId = order["apiloOrderId"] as? String ?? ""
            let platform = order["platformName"] as? String ?? ""
            for s in (order["skus"] as? [Any]) ?? [] {
                var sku = ""
                var qty = 1
                if let o = s as? [String: Any] {
                    sku = (o["sku"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                    qty = (o["quantity"] as? NSNumber)?.intValue ?? 1
                } else if let str = s as? String {
                    sku = str.trimmingCharacters(in: .whitespaces)
                }
                if !sku.isEmpty {
                    out.append(BrakiItem(
                        orderNumber: orderId, sku: sku, orderQuantity: qty,
                        platformName: platform, source: "apilo"
                    ))
                }
            }
        }
        return out
    }

    private func fetchBaselinker(profile: String) async throws -> [BrakiItem] {
        guard !helper.isEmpty else { return [] }
        let orders = try await OrdersApi.baselinkerOrders(helper: helper, profile: profile)
        var out: [BrakiItem] = []
        for order in orders {
            let orderId = order["orderNumber"] as? String ?? ""
            let platform = order["platformName"] as? String ?? ""
            let notatka = order["notatka"] as? String ?? ""
            for s in (order["skus"] as? [Any]) ?? [] {
                var sku = ""
                var qty = 1
                if let o = s as? [String: Any] {
                    sku = (o["sku"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                    qty = (o["quantity"] as? NSNumber)?.intValue ?? 1
                } else if let str = s as? String {
                    sku = str.trimmingCharacters(in: .whitespaces)
                }
                if !sku.isEmpty {
                    out.append(BrakiItem(
                        orderNumber: orderId, sku: sku, orderQuantity: qty,
                        platformName: platform, source: "baselinker", notatka: notatka
                    ))
                }
            }
        }
        return out
    }

    private func enrich(_ list: [BrakiItem]) async -> [BrakiItem] {
        // notatki apilo z helpera (po unikalnych numerach zamówień)
        var notesMap: [String: String] = [:]
        if !helper.isEmpty {
            let orderNumbers = Array(Set(list.filter { $0.source == "apilo" }.map { $0.orderNumber }.filter { !$0.isEmpty }))
            for ord in orderNumbers {
                if let note = try? await OrdersApi.orderNote(helper: helper, orderNumber: ord, db: db),
                   !note.isEmpty {
                    notesMap[ord] = note
                }
            }
        }

        var out = list
        for i in out.indices {
            let sku = out[i].sku
            if !sku.isEmpty, !apiAddress.isEmpty, !db.isEmpty, !user.name.isEmpty,
               let partObj = try? await PartApi.fetchPart(api: apiAddress, db: db, login: user.name, password: user.password, code: sku) {
                out[i].nazwa = partObj["nazwa"] as? String ?? ""
                out[i].photoUuid = (partObj["podstawoweZdjecie"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                out[i].lokalizacja = partObj["lokalizacja"] as? String ?? ""
            }
            if out[i].source == "apilo" {
                out[i].notatka = notesMap[out[i].orderNumber] ?? ""
            }
        }
        return out
    }

    private func saveNote() {
        guard let target = noteTarget else { return }
        let ord = target.orderNumber
        Task {
            let success: Bool
            if target.source == "baselinker" {
                success = (try? await OrdersApi.addBlNote(helper: helper, blOrderId: ord, note: noteText, db: db)) ?? false
            } else {
                success = (try? await OrdersApi.addOrderNote(helper: helper, orderNumber: ord, note: noteText, db: db)) ?? false
            }
            if success {
                toast = "Notatka zapisana"
                showNoteDialog = false
                fetchAll()
            } else {
                toast = "Błąd zapisu notatki"
            }
        }
    }

    private func markFound(_ entry: BrakiItem) {
        let ord = entry.orderNumber
        guard !ord.isEmpty, !helper.isEmpty else { return }
        Task {
            let ok = (try? await OrdersApi.changeApiloStatus(helper: helper, orderId: ord, db: db)) ?? false
            toast = ok ? "Status zamówienia zmieniony" : "Błąd zmiany statusu"
            if ok { fetchAll() }
        }
    }
}

// Miniatura 72×48 przez PhotoCache (jak na Androidzie fetchPhotoBlocking)
private struct BrakiThumb: View {
    let api: String
    let db: String
    let user: User
    let uuid: String

    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.lightGray).opacity(0.4))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text("Brak").font(.caption2)
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: 4))
            .task(id: uuid) {
                guard !uuid.isEmpty else { return }
                if let cached = PhotoCache.shared.get(uuid), let img = UIImage(data: cached) {
                    image = img
                    return
                }
                if let data = await PartApi.fetchPhoto(api: api, db: db, login: user.name, password: user.password, uuid: uuid) {
                    PhotoCache.shared.put(uuid, data)
                    image = UIImage(data: data)
                }
            }
    }
}
