import SwiftUI

// Port PartPhotosActivity.kt — siatka zdjęć części + podgląd pełnoekranowy z zoomem
struct PartPhotosView: View {
    let db: String
    let user: User
    let partId: String

    private var apiAddress: String { Prefs.apiAddress }

    @State private var codes: [String] = []
    @State private var loading = true
    @State private var error: String?
    @State private var preview: UIImage?
    @State private var showPreview = false
    @State private var previewLoading = false

    // zoom podglądu
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let e = error {
                Text(e).foregroundStyle(.red).padding(16)
            } else if codes.isEmpty {
                Text("Brak zdjęć").foregroundStyle(.secondary).padding(16)
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Zdjęcia części")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadList() }
        .overlay { if showPreview { previewOverlay } }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(codes, id: \.self) { code in
                    PhotoThumb(api: apiAddress, db: db, user: user, uuid: code) {
                        openPreview(code)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Podgląd pełnoekranowy (jak Dialog na Androidzie)
    private var previewOverlay: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
                .onTapGesture { closePreview() }

            if let img = preview {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { v in scale = min(max(lastScale * v.magnification, 1), 6) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .onTapGesture(count: 2) {
                        if scale > 1 {
                            resetZoom()
                        } else {
                            scale = 3; lastScale = 3
                        }
                    }
            } else if previewLoading {
                ProgressView().tint(.white)
            }

            HStack {
                Button("Reset") { resetZoom() }.foregroundStyle(.white)
                Spacer()
                Button("Zamknij") { closePreview() }.foregroundStyle(.white)
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func resetZoom() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }

    private func openPreview(_ code: String) {
        resetZoom()
        if let cached = PhotoCache.shared.get(code), let img = UIImage(data: cached) {
            preview = img
            showPreview = true
            return
        }
        preview = nil
        previewLoading = true
        showPreview = true
        Task {
            if let data = await PartApi.fetchPhoto(api: apiAddress, db: db, login: user.name, password: user.password, uuid: code) {
                PhotoCache.shared.put(code, data)
                preview = UIImage(data: data)
            }
            previewLoading = false
        }
    }

    private func closePreview() {
        showPreview = false
        preview = nil
    }

    private func loadList() async {
        guard !partId.isEmpty, !apiAddress.isEmpty else {
            loading = false
            error = "Brak danych części"
            return
        }
        loading = true
        error = nil
        do {
            codes = try await PartApi.photoList(api: apiAddress, db: db, login: user.name, password: user.password, partId: partId)
        } catch let e {
            codes = []
            self.error = "Błąd pobierania listy zdjęć: \(e.localizedDescription)"
        }
        loading = false
    }
}

// Kafelek miniatury (jak PhotoThumbnail na Androidzie)
private struct PhotoThumb: View {
    let api: String
    let db: String
    let user: User
    let uuid: String
    let onTap: () -> Void

    @State private var img: UIImage?
    @State private var loading = true

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(.gray.opacity(0.35))
                    if loading {
                        ProgressView()
                    } else if let img {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Text("Brak").foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
            .onTapGesture { if !loading && img != nil { onTap() } }
            .task { await load() }
    }

    private func load() async {
        if let cached = PhotoCache.shared.get(uuid) {
            img = UIImage(data: cached)
            loading = false
            return
        }
        if let data = await PartApi.fetchPhoto(api: api, db: db, login: user.name, password: user.password, uuid: uuid) {
            PhotoCache.shared.put(uuid, data)
            img = UIImage(data: data)
        }
        loading = false
    }
}

// Odpowiednik PhotoCache.kt — pamięciowy cache UUID → bytes (max 200 wpisów, LRU)
final class PhotoCache: @unchecked Sendable {
    static let shared = PhotoCache()
    private var map: [String: Data] = [:]
    private let lock = NSLock()

    func get(_ id: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let d = map[id] else { return nil }
        map.removeValue(forKey: id)
        map[id] = d // odśwież LRU
        return d
    }

    func put(_ id: String, _ data: Data) {
        lock.lock(); defer { lock.unlock() }
        map[id] = data
        if map.count > 200, let oldest = map.keys.first {
            map.removeValue(forKey: oldest)
        }
    }
}
