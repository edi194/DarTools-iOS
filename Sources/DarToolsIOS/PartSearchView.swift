import SwiftUI

// Port PartSearchActivity.kt — "Szukanie części".
// Pominięte: Zebra addons (dialog skanowania SKU, przycisk +), ManualPartSearch
// (przycisk zębatki — do zrobienia), Snackbar → toast.
struct PartSearchView: View {
    let db: String
    let user: User

    @ObservedObject private var net = NetworkStatus.shared

    private var helper: String { Prefs.apilohelperApi }
    private var apiAddress: String { Prefs.apiAddress }

    // profil wg PartSearch (fallback = profil samej bazy, inaczej niż w Braki)
    private var profile: String { OrdersApi.profileDefault(db) }

    @State private var isLoading = false
    @State private var error: String?
    @State private var loaded = false
    @State private var groups: [OrderGroup] = []
    @State private var hiddenItems: Set<String> = []

    @State private var isMarkingDamaged = false
    @State private var isMarkingOutOfStock = false
    @State private var isMarkingFound = false

    @State private var showPaletaPackageDialog = false
    @State private var groupForPaletaPackage: OrderGroup?

    @State private var selectedLocationFilter = "Wszystkie"
    @State private var selectedPlatforms: Set<String>?
    @State private var showPlatformFilterDialog = false
    @State private var tempPlatforms: Set<String> = []

    @State private var selectedGroup: OrderGroup?
    @State private var showPartChooser = false
    @State private var showMarkPart = false
    @State private var markAction: String? // "FOUND" / "NOT_FOUND"
    @State private var itemStatuses: [String: String] = [:]

    @State private var showNoteDialog = false
    @State private var noteField = ""
    @State private var noteOrderNumber = ""
    @State private var noteIsBaselinker = false
    @State private var orderNotes: [String: String] = [:]

    @State private var toast: String?
    @State private var showManualSearch = false
    @State private var pendingSku: String?

    private var isAnyLoading: Bool { isMarkingDamaged || isMarkingOutOfStock || isMarkingFound }

    private func statusKey(_ orderId: String, _ sku: String) -> String { "\(orderId)||\(sku)" }

    private func statusRowColor(_ status: String?, fallback: Color) -> Color {
        switch status {
        case "found": return Color(red: 0.647, green: 0.839, blue: 0.655)
        case "not_found": return Color(red: 0.937, green: 0.604, blue: 0.604)
        default: return fallback
        }
    }

    // MARK: - Pochodne
    private var filteredGroups: [OrderGroup] {
        let visible = groups.filter { !hiddenItems.contains($0.apiloOrderId) }
        let byPlatform: [OrderGroup]
        if let sel = selectedPlatforms {
            byPlatform = visible.filter { sel.contains($0.platformName) }
        } else {
            byPlatform = visible
        }
        let filtered: [OrderGroup]
        if selectedLocationFilter == "Wszystkie" {
            filtered = byPlatform
        } else {
            filtered = byPlatform.filter { g in
                g.items.contains { OrdersApi.locationCategory($0.lokalizacja) == selectedLocationFilter }
            }
        }
        if selectedLocationFilter.lowercased().hasPrefix("hala antresola") {
            return OrdersApi.sortHala(filtered)
        }
        return filtered
    }

    private var groupedItems: [(String, [OrderGroup])] {
        let byPlatform = Dictionary(grouping: filteredGroups, by: { $0.platformName })
        return byPlatform.keys.sorted().map { ($0, byPlatform[$0] ?? []) }
    }

    private var locationCategories: [String] { OrdersApi.locationCategories(groups) }

    private var allPlatforms: [String] { groups.map { $0.platformName }.sorted() }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            if let e = error {
                Spacer()
                Text(e)
                    .foregroundStyle(.red)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(16)
                Spacer()
            } else if !loaded {
                Spacer()
                VStack(spacing: 8) {
                    Text("Kliknij „Pobierz zamówienia\" aby załadować listę")
                        .multilineTextAlignment(.center)
                    Text("Baza: \(db)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        filterCard
                        if groupedItems.isEmpty {
                            Text("Brak zamówień dla wybranej lokalizacji")
                                .padding(32)
                        } else {
                            ForEach(groupedItems, id: \.0) { platform, platformItems in
                                Text("\(platform) (\(platformItems.count))")
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                                ForEach(platformItems) { group in
                                    orderCard(group, note: orderNotes[group.apiloOrderId])
                                }
                            }
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(12)
                }
            }
        }
        .navigationTitle("Zamówienia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(db) | Łącznie: \(filteredGroups.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toast($toast)
        .navigationDestination(isPresented: $showManualSearch) {
            ManualPartSearchView(db: db, user: user)
        }
        .navigationDestination(isPresented: Binding(
            get: { pendingSku != nil },
            set: { if !$0 { pendingSku = nil } }
        )) {
            PartInfoView(db: db, user: user, initialCode: pendingSku ?? "")
        }
        .sheet(item: $selectedGroup) { groupSheet($0) }
        .sheet(isPresented: $showPlatformFilterDialog) { platformFilterSheet }
        .alert("Wybierz typ przesyłki", isPresented: Binding(
            get: { showPaletaPackageDialog && groupForPaletaPackage != nil },
            set: { if !$0 { showPaletaPackageDialog = false; groupForPaletaPackage = nil } }
        )) {
            Button("Paleta") { markOrderFound(groupForPaletaPackage, status: 39, label: "Paleta") }
            Button("Paczka") { markOrderFound(groupForPaletaPackage, status: 42, label: "Paczka") }
            Button("Anuluj", role: .cancel) { groupForPaletaPackage = nil }
        } message: {
            Text("Czy to paleta czy paczka?\nWysyłka: \(shippingCostText(groupForPaletaPackage))")
        }
        .alert("Notatka wewnętrzna", isPresented: $showNoteDialog) {
            TextField("Treść notatki", text: $noteField, axis: .vertical)
            Button("OK") { saveNote() }
            Button("Anuluj", role: .cancel) {}
        }
    }

    private func shippingCostText(_ g: OrderGroup?) -> String {
        g?.kosztWysylki.map { String(format: "%.2f", $0) } ?? "-"
    }

    // MARK: - Górny filtr
    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filtruj po lokalizacji:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Menu {
                    ForEach(locationCategories, id: \.self) { cat in
                        Button("\(cat) (\(categoryCount(cat)))") {
                            selectedLocationFilter = cat
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedLocationFilter)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                Button("Grupy") {
                    tempPlatforms = selectedPlatforms ?? Set(allPlatforms)
                    showPlatformFilterDialog = true
                }
                .buttonStyle(.glassProminent)
            }

            if selectedLocationFilter != "Wszystkie" || selectedPlatforms != nil {
                Text("Wyświetlono: \(filteredGroups.count) z \(groups.count)")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func categoryCount(_ cat: String) -> Int {
        if cat == "Wszystkie" { return groups.count }
        return groups.filter { g in
            g.items.contains { OrdersApi.locationCategory($0.lokalizacja) == cat }
        }.count
    }

    // MARK: - Dolny pasek
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                showManualSearch = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .circle)
            }
            .accessibilityLabel("Ręczne wyszukiwanie części")

            PrimaryActionBar(
                title: loaded ? "Odśwież zamówienia" : "Pobierz zamówienia",
                systemImage: "arrow.clockwise",
                isLoading: isLoading,
                disabled: isLoading
            ) { fetchAll() }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Karta zamówienia
    private func orderCard(_ item: OrderGroup, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(item.items.count > 1
                     ? (item.baselinker ? "BL - \(item.apiloOrderId)" : item.apiloOrderId)
                     : item.primarySku)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let d = OrdersApi.formatOrderDate(item.dataZamowienia) {
                    Text(d)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Text("Wysyłka: \(shippingCostText(item))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if item.items.count == 1 {
                singleItemRow(item, part: item.items[0])
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(item.items.enumerated()), id: \.offset) { idx, part in
                        groupItemRow(order: item, part: part)
                        if idx < item.items.count - 1 {
                            Divider()
                        }
                    }
                    HStack {
                        Spacer()
                        Text("Suma: \(item.totalQuantity)")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    .padding(.top, 6)
                }
            }

            if let note, !note.isEmpty {
                Text("Notatka: \(note)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(red: 1.0, green: 0.65, blue: 0.15), in: .rect(cornerRadius: 6))
            }
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .contentShape(.rect)
        .onTapGesture { selectedGroup = item }
    }

    private func singleItemRow(_ group: OrderGroup, part: OrderItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.baselinker ? "BL - \(part.apiloOrderId)" : part.apiloOrderId)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                if !part.markaPojazdu.isEmpty {
                    Text(part.markaPojazdu).font(.caption).foregroundStyle(.secondary)
                }
                Text(part.nazwa).font(.subheadline)
                Text(part.lokalizacja).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(part.quantity)")
                .font(.title2.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.tint.opacity(0.15), in: .rect(cornerRadius: 4))

            Base64Thumb(b64: part.zdjecieBase64, size: 80)
        }
    }

    private func groupItemRow(order: OrderGroup, part: OrderItem) -> some View {
        let status = itemStatuses[statusKey(order.apiloOrderId, part.sku)]
        let rowBg: Color
        switch status {
        case "found": rowBg = Color(red: 0.647, green: 0.839, blue: 0.655)
        case "not_found": rowBg = Color(red: 0.937, green: 0.604, blue: 0.604)
        default: rowBg = .clear
        }
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(part.sku).font(.subheadline.weight(.medium))
                if !part.markaPojazdu.isEmpty {
                    Text(part.markaPojazdu).font(.caption).foregroundStyle(.secondary)
                }
                Text(part.nazwa).font(.subheadline.weight(.semibold))
                Text(part.lokalizacja).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(part.quantity)")
                .font(.headline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.tint.opacity(0.15), in: .rect(cornerRadius: 4))

            Base64Thumb(b64: part.zdjecieBase64, size: 72)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(rowBg, in: .rect(cornerRadius: 4))
    }

    // MARK: - Sheet grupy (szczegóły zamówienia)
    private func groupSheet(_ group: OrderGroup) -> some View {
        let isAllegroSMS = ["allegro", "sms"].contains(group.platformName.lowercased())
        let foundCount = group.items.filter { itemStatuses[statusKey(group.apiloOrderId, $0.sku)] == "found" }.count
        let notFoundCount = group.items.filter { itemStatuses[statusKey(group.apiloOrderId, $0.sku)] == "not_found" }.count
        let allPartsFound = group.items.allSatisfy { itemStatuses[statusKey(group.apiloOrderId, $0.sku)] == "found" }

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // nagłówek z informacjami
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.baselinker ? "Zamówienie: BL - \(group.apiloOrderId)" : "Zamówienie: \(group.apiloOrderId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let d = OrdersApi.formatOrderDate(group.dataZamowienia) {
                            Text(d).font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        Text("Platforma: \(group.platformName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Pozycji: \(group.items.count) · Suma ilości: \(group.totalQuantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if group.items.count > 1 {
                            Text("Znalezione: \(foundCount) · Nieznalezione: \(notFoundCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))

                    sheetButton("Pokaż informacje o części", icon: "info.circle", tint: .accentColor, disabled: isAnyLoading) {
                        if group.items.count <= 1 {
                            pendingSku = group.items.first?.sku
                            selectedGroup = nil
                        } else {
                            showPartChooser = true
                        }
                    }

                    if group.items.count > 1 {
                        HStack(spacing: 8) {
                            sheetButton("Znalezione", tint: Color(red: 0.647, green: 0.839, blue: 0.655), disabled: isAnyLoading) {
                                markAction = "FOUND"
                                showMarkPart = true
                            }
                            sheetButton("Nieznalezione", tint: Color(red: 0.937, green: 0.604, blue: 0.604), disabled: isAnyLoading) {
                                let unmarked = group.items.filter { itemStatuses[statusKey(group.apiloOrderId, $0.sku)] == nil }
                                if unmarked.count == 1, let only = unmarked.first {
                                    itemStatuses[statusKey(group.apiloOrderId, only.sku)] = "not_found"
                                } else {
                                    markAction = "NOT_FOUND"
                                    showMarkPart = true
                                }
                            }
                        }
                    }

                    sheetButton("Oznacz jako znalezione", tint: .accentColor, disabled: isAnyLoading || (group.items.count > 1 && !allPartsFound), spinning: isMarkingFound) {
                        if isAllegroSMS {
                            groupForPaletaPackage = group
                            showPaletaPackageDialog = true
                        } else {
                            markOrderFound(group, status: OrdersApi.foundStatus(group.platformName), label: "")
                        }
                    }

                    sheetButton("Oznacz jako brak towaru", tint: .orange, disabled: isAnyLoading, spinning: isMarkingOutOfStock) {
                        markOutOfStock(group)
                    }

                    if isAllegroSMS {
                        sheetButton("Oznacz jako uszkodzona", tint: .red, disabled: isAnyLoading, spinning: isMarkingDamaged) {
                            markDamaged(group)
                        }
                    }

                    sheetButton("Dodaj notatkę", tint: .accentColor, disabled: isAnyLoading) {
                        openNote(group)
                    }
                }
                .padding(16)
            }
            .navigationTitle(group.items.count > 1 ? "Zamówienie" : group.primarySku)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") { selectedGroup = nil }
                        .disabled(isAnyLoading)
                }
            }
            .navigationDestination(isPresented: $showPartChooser) { partChooserList(group) }
            .navigationDestination(isPresented: $showMarkPart) { markPartList(group) }
            .interactiveDismissDisabled(isAnyLoading)
        }
        .presentationDetents([.medium, .large])
    }

    private func sheetButton(
        _ title: String, icon: String? = nil, tint: Color,
        disabled: Bool = false, spinning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if spinning { ProgressView().controlSize(.small) }
                if let icon { Image(systemName: icon) }
                Text(title)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .disabled(disabled)
    }

    // MARK: - Wybór części (grupy >1)
    private func partChooserList(_ group: OrderGroup) -> some View {
        List(group.items, id: \.sku) { part in
            partSelectionRow(sku: part.sku, nazwa: part.nazwa, quantity: part.quantity, supporting: part.lokalizacja) {
                pendingSku = part.sku
                selectedGroup = nil
            }
        }
        .listStyle(.plain)
        .navigationTitle("Wybierz część do wyświetlenia")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Oznaczanie pojedynczej części
    private func markPartList(_ group: OrderGroup) -> some View {
        List(group.items, id: \.sku) { part in
            partSelectionRow(
                sku: part.sku, nazwa: part.nazwa, quantity: part.quantity,
                supporting: part.lokalizacja,
                containerColor: statusRowColor(itemStatuses[statusKey(group.apiloOrderId, part.sku)], fallback: Color(.secondarySystemBackground).opacity(0.22))
            ) {
                itemStatuses[statusKey(group.apiloOrderId, part.sku)] = (markAction == "FOUND") ? "found" : "not_found"
                showMarkPart = false
                markAction = nil
            }
        }
        .listStyle(.plain)
        .navigationTitle(markAction == "FOUND" ? "Oznacz część jako znalezioną" : "Oznacz część jako nieznalezioną")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func partSelectionRow(
        sku: String, nazwa: String, quantity: Int, supporting: String,
        containerColor: Color = Color(.secondarySystemBackground).opacity(0.25),
        onClick: @escaping () -> Void
    ) -> some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sku).font(.body.weight(.bold)).lineLimit(1)
                    if !nazwa.isEmpty {
                        Text(nazwa).font(.caption).lineLimit(2)
                    }
                    if !supporting.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(supporting).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("x\(quantity)")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.15), in: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(containerColor, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Filtrowanie platform
    private var platformFilterSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Odznacz platformy, które chcesz ukryć")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(allPlatforms, id: \.self) { platform in
                    let checked = tempPlatforms.contains(platform)
                    let count = groups.filter { $0.platformName == platform }.count
                    Button {
                        if checked { tempPlatforms.remove(platform) } else { tempPlatforms.insert(platform) }
                    } label: {
                        HStack {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                            Text(platform)
                                .lineLimit(1)
                            Spacer()
                            Text("(\(count))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Zaznacz platformy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Anuluj") { showPlatformFilterDialog = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zastosuj") {
                        selectedPlatforms = tempPlatforms.count == allPlatforms.count ? nil : tempPlatforms
                        showPlatformFilterDialog = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Logika
    private func fetchAll() {
        guard !helper.isEmpty else {
            error = "Brak skonfigurowanego adresu ApiloHelper API w ustawieniach"
            return
        }
        selectedGroup = nil
        showPartChooser = false
        showMarkPart = false
        markAction = nil
        showPaletaPackageDialog = false
        groupForPaletaPackage = nil
        showNoteDialog = false
        isLoading = true
        error = nil
        Task {
            do {
                let items = try await OrdersApi.orders(helper: helper, profile: profile)
                groups = OrdersApi.group(items)
                selectedLocationFilter = "Wszystkie"
                hiddenItems = []
                itemStatuses = [:]
                selectedPlatforms = nil
                loaded = true
                fetchNotes()
            } catch let e {
                self.error = "Błąd pobierania zamówień: \(e.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func fetchNotes() {
        guard !helper.isEmpty else {
            orderNotes = [:]
            return
        }
        let snapshot = groups
        Task {
            var map: [String: String] = [:]
            for g in snapshot {
                let note: String?
                if g.baselinker, let n = g.notatka, !n.trimmingCharacters(in: .whitespaces).isEmpty {
                    note = n
                } else {
                    note = try? await OrdersApi.orderNote(helper: helper, orderNumber: g.apiloOrderId, db: db)
                }
                if let n = note, !n.trimmingCharacters(in: .whitespaces).isEmpty {
                    map[g.apiloOrderId] = n
                }
            }
            orderNotes = map
        }
    }

    private func markOrderFound(_ group: OrderGroup?, status: Int?, label: String) {
        guard let group else { return }
        let orderId = group.apiloOrderId
        isMarkingFound = true
        Task {
            var success = false
            do {
                if group.baselinker {
                    success = try await OrdersApi.changeStatus(
                        helper: helper, profile: profile, orderId: orderId,
                        isBaselinker: true, originalStatus: group.statusId
                    )
                } else {
                    success = try await OrdersApi.changeStatus(
                        helper: helper, profile: profile, orderId: orderId, status: status
                    )
                }
            } catch { success = false }
            if success {
                hiddenItems.insert(orderId)
                selectedGroup = nil
                showPaletaPackageDialog = false
                groupForPaletaPackage = nil
                toast = label.isEmpty
                    ? "Zamówienie oznaczone jako znalezione"
                    : "Zamówienie oznaczone jako znalezione (\(label))"
            } else {
                toast = "Błąd oznaczania zamówienia"
            }
            isMarkingFound = false
        }
    }

    private func markOutOfStock(_ group: OrderGroup) {
        let orderId = group.apiloOrderId
        isMarkingOutOfStock = true
        Task {
            // dopisz brakujące SKU do notatki (dla części oznaczonych jako nieznalezione)
            let missing = group.items.map { $0.sku }.filter { itemStatuses[statusKey(orderId, $0)] == "not_found" }
            if !missing.isEmpty, !helper.isEmpty {
                var existing = orderNotes[orderId] ?? ""
                if existing.isEmpty {
                    existing = (try? await OrdersApi.orderNote(helper: helper, orderNumber: orderId, db: db)) ?? ""
                }
                let brakPart = "BRAK \(missing.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
                let newNote = existing.isEmpty ? brakPart : existing + " | " + brakPart
                let saved = (try? await OrdersApi.addOrderNote(helper: helper, orderNumber: orderId, note: newNote, db: db)) ?? false
                if saved {
                    orderNotes[orderId] = newNote
                } else {
                    toast = "Nie udało się zapisać notatki o brakach"
                }
            }

            var success = false
            do {
                if group.baselinker {
                    let outOfStock = OrdersApi.outOfStockStatus(profile: profile, statusId: group.statusId)
                    success = try await OrdersApi.changeStatus(
                        helper: helper, profile: profile, orderId: orderId,
                        status: outOfStock, isBaselinker: true, originalStatus: group.statusId
                    )
                } else {
                    success = try await OrdersApi.changeStatus(
                        helper: helper, profile: profile, orderId: orderId,
                        status: OrdersApi.outOfStockStatus(group.platformName)
                    )
                }
            } catch { success = false }

            if success {
                hiddenItems.insert(orderId)
                selectedGroup = nil
                toast = "Zamówienie oznaczone jako brak towaru"
            } else {
                toast = "Błąd oznaczania zamówienia"
            }
            isMarkingOutOfStock = false
        }
    }

    private func markDamaged(_ group: OrderGroup) {
        let orderId = group.apiloOrderId
        isMarkingDamaged = true
        Task {
            var success = false
            do {
                if group.baselinker {
                    success = try await OrdersApi.changeStatus(
                        helper: helper, profile: profile, orderId: orderId,
                        isBaselinker: true, originalStatus: group.statusId
                    )
                } else {
                    success = try await OrdersApi.changeStatus(
                        helper: helper, profile: profile, orderId: orderId, status: 27
                    )
                }
            } catch { success = false }
            if success {
                hiddenItems.insert(orderId)
                selectedGroup = nil
                toast = "Zamówienie oznaczone jako uszkodzone"
            } else {
                toast = "Błąd oznaczania zamówienia"
            }
            isMarkingDamaged = false
        }
    }

    private func openNote(_ group: OrderGroup) {
        noteOrderNumber = group.apiloOrderId
        noteIsBaselinker = group.baselinker
        if let existing = orderNotes[group.apiloOrderId], !existing.isEmpty {
            noteField = existing
            showNoteDialog = true
        } else if group.baselinker, let n = group.notatka, !n.isEmpty {
            noteField = n
            showNoteDialog = true
        } else {
            Task {
                let fetched = (try? await OrdersApi.orderNote(helper: helper, orderNumber: group.apiloOrderId, db: db)) ?? ""
                if !fetched.isEmpty {
                    orderNotes[group.apiloOrderId] = fetched
                }
                noteField = fetched
                showNoteDialog = true
            }
        }
    }

    private func saveNote() {
        let ord = noteOrderNumber
        Task {
            let success: Bool
            if noteIsBaselinker {
                success = (try? await OrdersApi.addBlNote(helper: helper, blOrderId: ord, note: noteField, db: db)) ?? false
            } else {
                success = (try? await OrdersApi.addOrderNote(helper: helper, orderNumber: ord, note: noteField, db: db)) ?? false
            }
            if success {
                orderNotes[ord] = noteField
                toast = "Notatka zapisana"
                showNoteDialog = false
            } else {
                toast = "Błąd zapisu notatki"
            }
        }
    }
}

// Miniatura z base64 (jak BitmapFactory na Androidzie), z prostym cache
nonisolated(unsafe) private let base64ThumbCache = NSCache<NSString, UIImage>()

private struct Base64Thumb: View {
    let b64: String
    let size: CGFloat

    var body: some View {
        let img: UIImage? = {
            guard !b64.isEmpty else { return nil }
            if let c = base64ThumbCache.object(forKey: b64 as NSString) { return c }
            guard let data = Data(base64Encoded: b64), let ui = UIImage(data: data) else { return nil }
            base64ThumbCache.setObject(ui, forKey: b64 as NSString)
            return ui
        }()
        Group {
            if let img {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Text("Brak")
                    .font(.caption2)
            }
        }
        .frame(width: size, height: size)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 8))
    }
}
