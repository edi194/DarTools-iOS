import SwiftUI

// Port QuickPartsActivity.kt — "Podręczna lista części".
// Pominięte: DataWedge (zastąpiony pigułką aparatu), wewnętrzna klawiatura.
struct QuickPartsView: View {
    let db: String
    let user: User

    @ObservedObject private var net = NetworkStatus.shared

    struct QuickItem: Identifiable {
        let id: String // ID części
        let action: String
        var checked = false
    }

    @State private var items: [QuickItem] = []
    @State private var selectAll = false
    @State private var showAddDialog = false
    @State private var newId = ""
    @State private var showActionDialog = false
    @State private var toast: String?
    @State private var showScanner = false
    // przejście do masowego złomowania
    @State private var scrapIds: [String] = []
    @State private var showMassScrap = false
    @State private var openPart: String?

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Spacer()
                Text("Brak pozycji na liście")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        row(for: item)
                    }
                    .listRowSeparator(.hidden)
                    Color.clear.frame(height: 48)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.insetGrouped)
                .listRowBackground(Color.clear)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Podręczna lista części")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newId = ""
                    showAddDialog = true
                } label: {
                    Image(systemName: "plus").font(.title3.weight(.medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dodaj")
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .overlay(alignment: .bottom) {
            // Android wypełniał pole ID skanem z DataWedge gdy dialog otwarty —
            // na iOS skan otwiera dialog z gotowym ID
            CameraPill(showScanner: $showScanner, visible: !showAddDialog, bottomInset: 100) { scanned in
                let digits = scanned.filter { $0.isNumber }
                guard digits.count >= 3 else { return }
                newId = digits
                showAddDialog = true
            }
        }
        .toast($toast)
        .alert("Dodaj ID", isPresented: $showAddDialog) {
            TextField("ID części", text: $newId)
                .keyboardType(.numberPad)
            Button("Złomowanie") { addQuick("złomowanie") }
            Button("Weryfikacja") { addQuick("weryfikacja") }
            Button("Anuluj", role: .cancel) {}
        }
        .alert("Wybierz akcję", isPresented: $showActionDialog) {
            Button("Usuń") {
                items.removeAll { $0.checked }
                syncChecked()
                persist()
            }
            Button("Złomuj") { startMassScrap() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Wybierz jedną z dostępnych akcji dla zaznaczonych pozycji.")
        }
        .navigationDestination(isPresented: $showMassScrap) {
            MassScrapView(db: db, user: user, ids: scrapIds)
        }
        .navigationDestination(isPresented: Binding(
            get: { openPart != nil },
            set: { if !$0 { openPart = nil } }
        )) {
            PartInfoView(db: db, user: user, initialCode: openPart ?? "")
        }
        .onAppear { load() }
    }

    // MARK: - Wiersz
    private func row(for item: QuickItem) -> some View {
        HStack(spacing: 10) {
            Button {
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx].checked.toggle()
                    syncChecked()
                }
            } label: {
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(item.checked ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.checked ? "Odznacz" : "Zaznacz")

            Button {
                openPart = item.id
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ID: \(item.id)")
                        .font(.body.weight(.medium))
                    Text("Akcja: \(item.action)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Dolny pasek
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                selectAll.toggle()
                for i in items.indices { items[i].checked = selectAll }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectAll ? "checkmark.square.fill" : "square")
                    Text("Zaznacz wszystko")
                }
                .font(.subheadline.weight(.medium))
                .frame(height: 52)
                .padding(.horizontal, 16)
                .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)

            PrimaryActionBar(
                title: "Akcja",
                systemImage: "bolt.fill",
                disabled: !items.contains { $0.checked }
            ) { showActionDialog = true }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Logika
    private func load() {
        items = QuickParts.load(user: user.name, db: db).map {
            QuickItem(
                id: ($0["id"] as? String) ?? "",
                action: ($0["action"] as? String) ?? "złomowanie",
                checked: false
            )
        }
        selectAll = false
    }

    private func syncChecked() {
        selectAll = !items.isEmpty && items.allSatisfy { $0.checked }
    }

    private func persist() {
        QuickParts.save(user: user.name, db: db, items: items.map { ["id": $0.id, "action": $0.action] })
    }

    private func addQuick(_ action: String) {
        defer { showAddDialog = false }
        let trimmed = newId.filter { $0.isNumber }
        guard !trimmed.isEmpty else { return }
        items.append(QuickItem(id: trimmed, action: action))
        persist()
        newId = ""
    }

    private func startMassScrap() {
        let ids = items.filter { $0.checked && $0.action == "złomowanie" }.map { $0.id }
        if !ids.isEmpty {
            scrapIds = ids
            showMassScrap = true
        } else if items.contains(where: { $0.checked }) {
            toast = "Brak zaznaczonych pozycji do złomowania"
        }
    }
}
