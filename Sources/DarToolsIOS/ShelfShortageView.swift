import SwiftUI

// Natywny checkbox na iOS (brak .checkbox w UIKit-SwiftUI)
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy) { configuration.isOn.toggle() }
        } label: {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

// Port ShelfShortageActivity.kt — „Braki półki": sprawdza polkoinator i przypisuje zaznaczone pozycje ponownie.
struct ShelfShortageView: View {
    let db: String
    let user: User
    let shelf: String // zeskanowany kod półki

    @ObservedObject private var net = NetworkStatus.shared

    private var apiAddress: String { Prefs.apiAddress }
    private var helper: String { Prefs.apilohelperApi }

    // SUS = odwrotność zeskanowanej: z "P" ucina, bez "P" dokleja
    private var normalizedShelf: String {
        let t = shelf.trimmingCharacters(in: .whitespaces)
        return t.lowercased().hasPrefix("p") ? String(t.dropFirst(1)) : "P\(t)"
    }

    private struct ShortageItem: Identifiable {
        let id: String
        var nazwa: String
        var ilosc: Int
        var checked = true
    }

    @State private var items: [ShortageItem] = []
    @State private var checking = false
    @State private var assigning = false
    @State private var error: String?
    @State private var message: String?
    @State private var toast: String?
    @State private var openPart: String?

    private var allChecked: Bool { !items.isEmpty && items.allSatisfy(\.checked) }
    private var checkedCount: Int { items.filter(\.checked).count }

    var body: some View {
        VStack(spacing: 0) {
            PrimaryActionBar(
                title: "Sprawdź",
                systemImage: "magnifyingglass",
                isLoading: checking,
                disabled: checking || assigning
            ) { check() }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let m = message {
                Text(m).font(.callout).foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 4)
            }
            if let e = error {
                Text(e).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 4)
            }

            if !items.isEmpty {
                HStack {
                    Toggle("", isOn: Binding(get: { allChecked }, set: setAllChecked))
                        .toggleStyle(CheckboxToggleStyle())
                        .labelsHidden()
                    Text("Zaznacz wszystko (\(checkedCount)/\(items.count))")
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($items) { $item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $item.checked)
                                .toggleStyle(CheckboxToggleStyle())
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ID: \(item.id)").font(.subheadline.weight(.semibold))
                                Text(item.nazwa).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Ilość: \(item.ilosc)").font(.caption)
                        }
                        .padding(10)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !item.id.isEmpty else { return }
                            openPart = item.id
                        }
                    }
                }
                .padding(12)
            }

            PrimaryActionBar(
                title: "Przypisz ponownie",
                systemImage: "arrow.uturn.backward.circle.fill",
                isLoading: assigning,
                disabled: assigning || checking || !items.contains(where: \.checked)
            ) { reassignChecked() }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationTitle("\(shelf) | SUS: \(normalizedShelf)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                }
            }
        }
        .navigationDestination(isPresented: Binding(get: { openPart != nil }, set: closePart)) {
            PartInfoView(db: db, user: user, initialCode: openPart ?? "")
        }
        .toast($toast)
    }

    private func setAllChecked(_ v: Bool) {
        for i in items.indices { items[i].checked = v }
    }

    private func closePart(_ open: Bool) {
        if !open { openPart = nil }
    }

    // MARK: - Logika (jak na Androidzie)
    private func check() {
        error = nil
        message = nil
        guard !helper.isEmpty else { error = "Brak skonfigurowanego apilohelper_api w ustawieniach"; return }
        guard !normalizedShelf.isEmpty else { error = "Brak kodu półki"; return }
        checking = true
        Task {
            do {
                let resp = try await PartApi.fetchShelfShortage(
                    helper: helper, profil: PartApi.profile(db), db: db, shelf: normalizedShelf)
                var out: [ShortageItem] = []
                for o in (resp["items"] as? [[String: Any]]) ?? [] {
                    let raw = o["id"]
                    let id = (raw as? String) ?? (raw as? NSNumber)?.stringValue ?? ""
                    if id.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    out.append(ShortageItem(
                        id: id,
                        nazwa: (o["nazwa"] as? String) ?? "-",
                        ilosc: (o["iloscPozostala"] as? NSNumber)?.intValue ?? 0
                    ))
                }
                items = out
                message = items.isEmpty ? "Brak pozycji do sprawdzenia" : "Pozycji do sprawdzenia: \(items.count)"
            } catch let e {
                error = e.localizedDescription
            }
            checking = false
        }
    }

    private func reassignChecked() {
        error = nil
        message = nil
        let toAssign = items.filter(\.checked)
        guard !toAssign.isEmpty else { error = "Zaznacz co najmniej jedną pozycję"; return }
        guard net.isOnline else { error = "Brak połączenia – tryb offline"; return }
        assigning = true
        Task {
            var okCount = 0
            var firstErr: String?
            for item in toAssign {
                do {
                    // półka po oryginalnym kodzie (bez normalizacji) — jak na Androidzie
                    let resp = try await PartApi.assignToShelf(
                        api: apiAddress, db: db, login: user.name, password: user.password,
                        part: item.id, shelf: shelf)
                    let kod = (resp["kod"] as? NSNumber)?.intValue ?? -1
                    if kod == 200, (resp["status"] as? String)?.lowercased() == "success" {
                        items.removeAll { $0.id == item.id }
                        okCount += 1
                    } else if firstErr == nil {
                        let kom = (resp["komunikat"] as? String) ?? ""
                        firstErr = kom.isEmpty ? "Błąd przypisania (\(kod)): część \(item.id)" : kom
                    }
                } catch let e {
                    if firstErr == nil { firstErr = "Błąd połączenia: \(e.localizedDescription)" }
                }
            }
            assigning = false
            if let f = firstErr {
                error = "\(f) (przypisano ponownie: \(okCount))"
            } else {
                message = "Przypisano ponownie: \(okCount)"
                toast = "Przypisano ponownie: \(okCount)"
            }
        }
    }
}
