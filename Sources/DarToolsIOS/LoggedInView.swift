import SwiftUI

// Ekran główny po zalogowaniu — siatka kafelków w stylu Liquid Glass.
// Natywny navigation bar (large title) zamiast własnego CompactHeader.
struct LoggedInScreen: View {
    let dbName: String
    let user: User
    let onLogout: () -> Void
    let onSwitchDb: () -> Void
    let onOpen: (AppRoute) -> Void

    @ObservedObject private var net = NetworkStatus.shared
    @State private var lastNotified: (apilo: Int, bl: Int)?

    private struct Tile: Identifiable {
        let title: String
        let systemImage: String
        let offlineAllowed: Bool
        var id: String { title }
    }

    private let mainTiles = [
        Tile(title: "Pokaż informacje\no części", systemImage: "shippingbox", offlineAllowed: false),
        Tile(title: "Informacje o półce", systemImage: "building.2", offlineAllowed: false),
        Tile(title: "Złomowanie", systemImage: "trash", offlineAllowed: true),
        Tile(title: "Odłóż na półkę", systemImage: "arrow.down.to.line", offlineAllowed: true),
    ]

    private let extraTiles = [
        Tile(title: "Przenieś półkę", systemImage: "arrow.left.arrow.right", offlineAllowed: false),
        Tile(title: "Podręczna lista części", systemImage: "list.bullet.rectangle", offlineAllowed: true),
        Tile(title: "Szukanie części", systemImage: "magnifyingglass", offlineAllowed: false),
        Tile(title: "Braki towaru", systemImage: "exclamationmark.triangle", offlineAllowed: false),
    ]

    var body: some View {
        VStack(spacing: 12) {
            userCard
            sectionLabel("Magazyn")
            tileRow(mainTiles[0], mainTiles[1])
            tileRow(mainTiles[2], mainTiles[3])
            sectionLabel("Dodatkowe")
            tileRow(extraTiles[0], extraTiles[1])
            tileRow(extraTiles[2], extraTiles[3])
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(dbName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // jak DbTaskActivity na Androidzie: sprawdzanie braków w tle ekranu głównego
            guard Prefs.autoRefreshBraki else { return }
            while !Task.isCancelled {
                if net.isOnline, let c = await BrakiAutoCheck.check(helper: Prefs.apilohelperApi, db: dbName),
                   (c.apilo > 0 || c.bl > 0), c.apilo != lastNotified?.apilo || c.bl != lastNotified?.bl {
                    Notif.braki(db: dbName, apiloOrders: c.apilo, blOrders: c.bl)
                    lastNotified = c
                }
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onLogout) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("Wyloguj")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    if !net.isOnline {
                        Text("Offline")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.red.opacity(0.85), in: .capsule)
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Button(action: onSwitchDb) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!net.isOnline)
                    .accessibilityLabel("Przełącz bazę")
                }
                .animation(.quick, value: net.isOnline)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func tileRow(_ a: Tile, _ b: Tile) -> some View {
        HStack(spacing: 12) {
            tileView(a)
            tileView(b)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Karta użytkownika
    private var userCard: some View {
        HStack(spacing: 14) {
            AvatarCircle(name: user.name)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(.headline)
                Text("Zalogowano do bazy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !net.isOnline {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    // MARK: - Kafelek
    private func tileView(_ tile: Tile) -> some View {
        let enabled = net.isOnline || tile.offlineAllowed
        return Button {
            open(tile)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: tile.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular, in: .circle)
                Text(tile.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(PressableTileStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
        .animation(.quick, value: net.isOnline)
    }

    private func open(_ tile: Tile) {
        switch tile.title {
        case let t where t.hasPrefix("Pokaż informacje"):
            onOpen(.partInfo(db: dbName, user: user, initialCode: nil))
        case "Informacje o półce":
            onOpen(.shelfInfo(db: dbName, user: user))
        case "Złomowanie":
            onOpen(.scrap(db: dbName, user: user))
        case "Odłóż na półkę":
            onOpen(.placeOnShelf(db: dbName, user: user))
        case "Przenieś półkę":
            onOpen(.moveShelf(db: dbName, user: user))
        case "Podręczna lista części":
            onOpen(.quickParts(db: dbName, user: user))
        case "Szukanie części":
            onOpen(.partSearch(db: dbName, user: user))
        case "Braki towaru":
            onOpen(.braki(db: dbName, user: user))
        default:
            break
        }
    }
}
