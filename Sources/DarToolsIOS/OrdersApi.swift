import Foundation

// Endpoints apilohelper — wspólne dla „Braki towaru" i „Szukanie części".
enum OrdersApi {
    private static func esc(_ s: String) -> String {
        s.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        ) ?? s
    }

    private static func base(_ addr: String) -> String {
        (addr.hasPrefix("http://") || addr.hasPrefix("https://")) ? addr : "http://\(addr)"
    }

    private static func urlStr(_ helper: String, _ path: String) throws -> URL {
        guard let u = URL(string: base(helper).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw ApiError.invalidPayload("Nieprawidłowy adres apilohelper")
        }
        return u
    }

    private static func send(_ req: URLRequest, timeout: Double) async throws -> (Data, Int) {
        var r = req
        r.timeoutInterval = timeout
        if r.value(forHTTPHeaderField: "Accept") == nil {
            r.setValue("*/*", forHTTPHeaderField: "Accept")
        }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        if !(200...299).contains(code) {
            throw ApiError.badStatus(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, code)
    }

    private static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Profile (mapowanie bazy, wariant PartSearch: fallback = profil samej bazy)

    static func profileDefault(_ db: String) -> String {
        for (key, value) in PartApi.profileAliases
        where db.range(of: key, options: .caseInsensitive) != nil { return value }
        return PartApi.profileStripped(db)
    }

    // Status "brak" dla Baselinker — profile wymagające własnego id statusu (uzupełnij wg potrzeb): ["profil": 123456]
    static let outOfStockByProfile: [String: Int] = [:]

    static func outOfStockStatus(profile: String, statusId: Int?) -> Int {
        if let override = outOfStockByProfile[profile] { return override }
        if statusId == 118031 || statusId == 125405 { return 120925 }
        return 119795
    }

    // MARK: - Braki towaru

    static func apiloOrders(helper: String, profile: String) async throws -> [[String: Any]] {
        if Dummy.on { return Dummy.apiloOrders() }
        let (data, _) = try await send(
            URLRequest(url: try urlStr(helper, "/apilo/orders-by-apilo-status?profile=\(esc(profile))")),
            timeout: 15
        )
        return (json(data)["orders"] as? [[String: Any]]) ?? []
    }

    static func baselinkerOrders(helper: String, profile: String) async throws -> [[String: Any]] {
        if Dummy.on { return Dummy.baselinkerOrders() }
        let (data, _) = try await send(
            URLRequest(url: try urlStr(helper, "/baselinker/orders-by-status?profile=\(esc(profile))")),
            timeout: 15
        )
        return (json(data)["orders"] as? [[String: Any]]) ?? []
    }

    // GET /order-note → nil, gdy brak pola "note"
    static func orderNote(helper: String, orderNumber: String, db: String) async throws -> String? {
        if Dummy.on { return Dummy.note() }
        guard !helper.isEmpty, !orderNumber.isEmpty else { return nil }
        let path = "/order-note?orderNumber=\(esc(orderNumber))&profile=\(esc(PartApi.profileStripped(db)))"
        let (data, _) = try await send(URLRequest(url: try urlStr(helper, path)), timeout: 10)
        let obj = json(data)
        return obj["note"] as? String
    }

    // POST /add-order-note (multipart) — true przy HTTP 2xx
    static func addOrderNote(helper: String, orderNumber: String, note: String, db: String) async throws -> Bool {
        if Dummy.on { return true }
        guard !helper.isEmpty, !orderNumber.isEmpty else { return false }
        let boundary = "----DarToolsBoundary\(Int(Date().timeIntervalSince1970 * 1000))"
        var req = URLRequest(url: try urlStr(helper, "/add-order-note?profile=\(esc(PartApi.profileStripped(db)))"))
        req.httpMethod = "POST"
        var body = ""
        func field(_ n: String, _ v: String) {
            body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n"
        }
        field("orderNumber", orderNumber)
        field("note", note)
        body += "--\(boundary)--\r\n"
        req.httpBody = Data(body.utf8)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, code) = try await send(req, timeout: 15)
        return (200...299).contains(code)
    }

    // POST /apilo/change-order-status → pole "ok"
    static func changeApiloStatus(helper: String, orderId: String, db: String) async throws -> Bool {
        if Dummy.on { return true }
        guard !helper.isEmpty, !orderId.isEmpty else { return false }
        let path = "/apilo/change-order-status?orderId=\(esc(orderId))&company=\(esc(PartApi.profileStripped(db)))"
        var req = URLRequest(url: try urlStr(helper, path))
        req.httpMethod = "POST"
        let (data, _) = try await send(req, timeout: 15)
        return (json(data)["ok"] as? Bool) ?? false
    }

    // MARK: - dt_mobile (Szukanie części)

    static func orders(helper: String, profile: String) async throws -> [OrderItem] {
        if Dummy.on { return Dummy.orderItems() }
        let (data, _) = try await send(
            URLRequest(url: try urlStr(helper, "/dt_mobile/orders?profile=\(esc(profile))")),
            timeout: 30
        )
        return ((json(data)["items"] as? [[String: Any]]) ?? []).map(OrderItem.init)
    }

    // PUT /dt_mobile/change-order-status → true przy HTTP 2xx
    static func changeStatus(
        helper: String, profile: String, orderId: String,
        status: Int? = nil, isBaselinker: Bool = false, originalStatus: Int? = nil
    ) async throws -> Bool {
        if Dummy.on { return true }
        var q = "profile=\(esc(profile))&orderId=\(esc(orderId))"
        if let s = status { q += "&status=\(s)" }
        if isBaselinker { q += "&isBaselinker=true" }
        if let o = originalStatus { q += "&originalStatus=\(o)" }
        var req = URLRequest(url: try urlStr(helper, "/dt_mobile/change-order-status?\(q)"))
        req.httpMethod = "PUT"
        let (_, code) = try await send(req, timeout: 30)
        return (200...299).contains(code)
    }

    // POST /dt_mobile/bl-note (puste body) → true przy HTTP 2xx
    static func addBlNote(helper: String, blOrderId: String, note: String, db: String) async throws -> Bool {
        if Dummy.on { return true }
        guard !helper.isEmpty, !blOrderId.isEmpty else { return false }
        let path = "/dt_mobile/bl-note?profile=\(esc(PartApi.profileStripped(db)))&blOrderId=\(esc(blOrderId))&note=\(esc(note))"
        var req = URLRequest(url: try urlStr(helper, path))
        req.httpMethod = "POST"
        req.httpBody = Data()
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let (_, code) = try await send(req, timeout: 15)
        return (200...299).contains(code)
    }

    // MARK: - Statusy

    static func outOfStockStatus(_ platformName: String) -> Int {
        switch platformName.lowercased() {
        case "allegro", "sms": return 36
        case "ovoko": return 57
        default: return 36
        }
    }

    static func foundStatus(_ platformName: String) -> Int {
        switch platformName.lowercased() {
        case "allegro", "sms": return 42
        case "ovoko": return 60
        default: return 42
        }
    }

    // MARK: - Formatowanie daty ("dd-MM-yyyy HH:mm" lub ISO → "dd-MM-yyyy HH:mm")
    private static let orderDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy HH:mm"
        f.locale = Locale(identifier: "pl_PL")
        return f
    }()

    static func formatOrderDate(_ raw: String?) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        if orderDateFmt.date(from: r) != nil { return r }
        if let d = ISO8601DateFormatter().date(from: r) { return orderDateFmt.string(from: d) }
        let plain = DateFormatter()
        plain.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = plain.date(from: r) { return orderDateFmt.string(from: d) }
        return nil
    }

    // MARK: - Grupy i lokalizacje

    static func group(_ items: [OrderItem]) -> [OrderGroup] {
        var order: [String] = []
        var buckets: [String: [OrderItem]] = [:]
        for it in items {
            if buckets[it.apiloOrderId] == nil { order.append(it.apiloOrderId) }
            buckets[it.apiloOrderId, default: []].append(it)
        }
        return order.map { id in
            let list = buckets[id] ?? []
            let first = list.first ?? OrderItem([:])
            return OrderGroup(
                apiloOrderId: id,
                platformName: first.platformName,
                items: list,
                totalQuantity: list.reduce(0) { $0 + $1.quantity },
                primarySku: first.sku,
                nazwa: first.nazwa,
                lokalizacja: first.lokalizacja,
                zdjecieBase64: first.zdjecieBase64,
                kosztWysylki: list.compactMap { $0.kosztWysylki }.first,
                dataZamowienia: first.dataZamowienia,
                baselinker: first.baselinker,
                statusId: first.statusId,
                notatka: first.notatka
            )
        }
    }

    static func locationCategory(_ lokalizacja: String) -> String {
        let t = lokalizacja.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "Brak lokalizacji" }
        let parts = t.components(separatedBy: "\\").map { $0.trimmingCharacters(in: .whitespaces) }
        let first = parts[0]
        if first.lowercased() == "hala antresola", parts.count >= 2, parts[1].lowercased().hasPrefix("poziom") {
            return "\(first) \\ \(parts[1])"
        }
        return first
    }

    static func locationCategories(_ groups: [OrderGroup]) -> [String] {
        let cats = Set(groups.flatMap { $0.items }.map { locationCategory($0.lokalizacja) })
        return ["Wszystkie"] + cats.sorted()
    }

    // Sortowanie HALA ANTRESOLA: POZIOM → RZĄD → REGAŁ → PÓŁKA (numerycznie)
    private static func numberAfterLabel(_ token: String, _ label: String) -> Int? {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix(label.lowercased()) else { return nil }
        let rest = t.dropFirst(label.count)
        return rest.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
    }

    private static func shelfParts(_ token: String) -> [Int] {
        var t = token.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("półka") {
            t = String(t.dropFirst("półka".count)).trimmingCharacters(in: .whitespaces)
        }
        return t.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    private static func compareHala(_ a: String, _ b: String) -> Bool {
        let pa = a.components(separatedBy: "\\").map { $0.trimmingCharacters(in: .whitespaces) }
        let pb = b.components(separatedBy: "\\").map { $0.trimmingCharacters(in: .whitespaces) }
        for (i, label) in ["poziom", "rząd", "regał"].enumerated() {
            let idx = i + 1
            let na = pa.count > idx ? numberAfterLabel(pa[idx], label) : nil
            let nb = pb.count > idx ? numberAfterLabel(pb[idx], label) : nil
            if na != nb { return (na ?? Int.min) < (nb ?? Int.min) }
        }
        let sa = pa.count > 4 ? shelfParts(pa[4]) : []
        let sb = pb.count > 4 ? shelfParts(pb[4]) : []
        return (sa.first ?? Int.min) < (sb.first ?? Int.min)
    }

    static func sortHala(_ groups: [OrderGroup]) -> [OrderGroup] {
        groups.sorted { compareHala($0.lokalizacja, $1.lokalizacja) }
    }
}

// MARK: - Modele

struct OrderItem {
    let sku: String
    let apiloOrderId: String
    let platformName: String
    let quantity: Int
    let nazwa: String
    let markaPojazdu: String
    let lokalizacja: String
    let kosztWysylki: Double?
    let dataZamowienia: String?
    let baselinker: Bool
    let statusId: Int?
    let notatka: String?
    let zdjecieBase64: String

    init(_ o: [String: Any]) {
        sku = o["sku"] as? String ?? ""
        apiloOrderId = o["apiloOrderId"] as? String ?? ""
        platformName = o["platformName"] as? String ?? ""
        quantity = (o["quantity"] as? NSNumber)?.intValue ?? 0
        nazwa = o["nazwa"] as? String ?? ""
        markaPojazdu = o["markaPojazdu"] as? String ?? ""
        lokalizacja = o["lokalizacja"] as? String ?? ""
        kosztWysylki = (o["kosztWysylki"] as? NSNumber)?.doubleValue
        dataZamowienia = o["datazamowienia"] as? String
        baselinker = (o["baselinker"] as? NSNumber)?.boolValue ?? false
        statusId = (o["statusId"] as? NSNumber)?.intValue
        notatka = o["notatka"] as? String
        zdjecieBase64 = o["zdjecieBase64"] as? String ?? ""
    }
}

struct OrderGroup: Identifiable {
    let apiloOrderId: String
    let platformName: String
    let items: [OrderItem]
    let totalQuantity: Int
    let primarySku: String
    let nazwa: String
    let lokalizacja: String
    let zdjecieBase64: String
    let kosztWysylki: Double?
    let dataZamowienia: String?
    let baselinker: Bool
    let statusId: Int?
    let notatka: String?
    var id: String { apiloOrderId }
}
