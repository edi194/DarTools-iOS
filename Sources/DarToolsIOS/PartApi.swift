import Foundation

// Odpowiednik PartInfoUtils.kt
enum PartApi {
    // MARK: - Base

    private static func base(_ addr: String) -> String {
        let t = addr.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "http://\(t)"
    }

    private static func url(_ addr: String, _ path: String) throws -> URL {
        guard let u = URL(string: base(addr).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw ApiError.invalidPayload("Nieprawidłowy adres API")
        }
        return u
    }

    private static func textRequest(_ req: URLRequest, timeout: Double = 7) async throws -> String {
        var r = req
        r.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: r)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ApiError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func withTimeout(_ req: URLRequest, _ t: Double) -> URLRequest {
        var r = req
        r.timeoutInterval = t
        return r
    }

    private static func jsonRequest(_ req: URLRequest, timeout: Double = 7) async throws -> [String: Any] {
        let text = try await textRequest(req, timeout: timeout)
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw ApiError.invalidPayload("Odpowiedź nie jest JSON-em")
        }
        return obj
    }

    // MARK: - Magazyn (API bazowe)

    static func fetchPart(api: String, db: String, login: String, password: String, code: String) async throws -> [String: Any] {
        if Dummy.on { return Dummy.part(code: code) }
        var req = URLRequest(url: try url(api, "/api/Magazyn/PobierzDaneCzesci"))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(db, forHTTPHeaderField: "BazaDanych")
        req.setValue(login, forHTTPHeaderField: "Nazwa")
        req.setValue(password, forHTTPHeaderField: "Haslo")
        req.setValue(code, forHTTPHeaderField: "KodKreskowy")
        let obj = try await jsonRequest(req)
        guard let dane = obj["dane"] as? [Any], let first = dane.first as? [String: Any] else {
            throw ApiError.invalidPayload("Brak danych części w odpowiedzi")
        }
        return first
    }

    static func fetchPhoto(api: String, db: String, login: String, password: String, uuid: String) async -> Data? {
        if Dummy.on { return Dummy.photo(uuid: uuid) }
        for attempt in 1...3 {
            do {
                var req = URLRequest(url: try url(api, "/api/Zdjecia/Pobierz"))
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(db, forHTTPHeaderField: "BazaDanych")
                req.setValue(login, forHTTPHeaderField: "Nazwa")
                req.setValue(password, forHTTPHeaderField: "Haslo")
                req.setValue(uuid, forHTTPHeaderField: "UUID")
                let obj = try await jsonRequest(req, timeout: 8)
                if let dane = obj["dane"] as? [Any],
                   let first = dane.first as? [String: Any],
                   let b64 = (first["dane"] as? String)?.trimmingCharacters(in: .whitespaces),
                   !b64.isEmpty,
                   let data = Data(base64Encoded: b64) {
                    return data
                }
                return nil
            } catch {
                if attempt < 3 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 300_000_000) }
            }
        }
        return nil
    }

    // Lista części na półce (/api/Magazyn/PobierzDanePolki, header KodKreskowy)
    static func fetchShelf(api: String, db: String, login: String, password: String, shelfCode: String) async throws -> [[String: Any]] {
        if Dummy.on { return Dummy.shelf() }
        var req = URLRequest(url: try url(api, "/api/Magazyn/PobierzDanePolki"))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(db, forHTTPHeaderField: "BazaDanych")
        req.setValue(login, forHTTPHeaderField: "Nazwa")
        req.setValue(password, forHTTPHeaderField: "Haslo")
        req.setValue(shelfCode, forHTTPHeaderField: "KodKreskowy")
        let obj = try await jsonRequest(req, timeout: 8)
        return obj["dane"] as? [[String: Any]] ?? []
    }

    // Odłóż na półkę — POST /api/Magazyn/OdlozNaPolke (liczy się kod+status w JSON)
    static func assignToShelf(api: String, db: String, login: String, password: String, part: String, shelf: String) async throws -> [String: Any] {
        if Dummy.on { return ["kod": 200, "status": "success"] }
        var req = URLRequest(url: try url(api, "/api/Magazyn/OdlozNaPolke"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "czesc_KodKreskowy": part,
            "polka_KodKreskowy": shelf,
        ])
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json-patch+json", forHTTPHeaderField: "Content-Type")
        req.setValue(db, forHTTPHeaderField: "BazaDanych")
        req.setValue(login, forHTTPHeaderField: "Nazwa")
        req.setValue(password, forHTTPHeaderField: "Haslo")
        let (data, resp) = try await URLSession.shared.data(for: withTimeout(req, 15))
        var obj: [String: Any] = [:]
        if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = parsed
        }
        if let http = resp as? HTTPURLResponse {
            obj["_httpCode"] = http.statusCode // fallback jak na Androidzie
        }
        return obj
    }

    // Złomowanie — POST /api/Magazyn/Zlomuj (status HTTP ignorowany, liczy się pole "kod" w JSON)
    static func scrap(api: String, db: String, login: String, password: String, code: String) async throws -> [String: Any] {
        if Dummy.on { return ["kod": 200, "status": "success"] }
        var req = URLRequest(url: try url(api, "/api/Magazyn/Zlomuj"))
        req.httpMethod = "POST"
        req.httpBody = Data(#"{"tekst":"string"}"#.utf8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json-patch+json", forHTTPHeaderField: "Content-Type")
        req.setValue(db, forHTTPHeaderField: "BazaDanych")
        req.setValue(login, forHTTPHeaderField: "Nazwa")
        req.setValue(password, forHTTPHeaderField: "Haslo")
        req.setValue(code, forHTTPHeaderField: "KodKreskowy")
        let (data, _) = try await URLSession.shared.data(for: withTimeout(req, 7))
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.invalidPayload("Odpowiedź nie jest JSON-em")
        }
        return obj
    }

    // Wyjątki mapowania baza -> profil ApiloHelper (nazwa profilu różni się od nazwy bazy).
    // Dodaj wpis dla firmy, której profil w API ma inną nazwę: ["NazwaBazy": "profil"]
    static let profileAliases: [String: String] = [:]

    // Mapowanie bazy -> profil dla apilohelper (osobna wersja: contains + strip niealfanumeryków)
    static func profileStripped(_ db: String) -> String {
        for (key, value) in profileAliases where db.range(of: key, options: .caseInsensitive) != nil {
            return value
        }
        return db.lowercased().filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    // darsoft-scrap-helper — wolny (do 60 s), POST z pustym ciałem
    static func scrapHelper(helper: String, db: String, login: String, password: String, id: String) async throws -> [String: Any] {
        if Dummy.on { return ["kod": 200, "status": "success"] }
        guard !helper.isEmpty else { throw ApiError.invalidPayload("Brak apilohelper_api w ustawieniach") }
        guard !id.isEmpty else { throw ApiError.invalidPayload("Brak id części") }
        let path = "/darsoft-scrap-helper?db=\(pathEsc(profileStripped(db)))&user=\(pathEsc(login))&haslo=\(pathEsc(password))&id=\(pathEsc(id))"
        var req = URLRequest(url: try url(helper, path))
        req.httpMethod = "POST"
        req.httpBody = Data()
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: withTimeout(req, 60))
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.invalidPayload("Pusta odpowiedź od helpera")
        }
        return obj
    }

    // Polkoinator — pozycje brakujące na półce (GET {helper}/polkoinator?profil=&db=&polkaId=)
    static func fetchShelfShortage(helper: String, profil: String, db: String, shelf: String) async throws -> [String: Any] {
        if Dummy.on {
            return ["items": (0..<Int.random(in: 2...6)).map { _ -> [String: Any] in
                let p = Dummy.part(code: "")
                return ["id": p["id"] ?? "", "nazwa": p["nazwa"] ?? "", "iloscPozostala": Int.random(in: 1...9)]
            }]
        }
        guard !helper.isEmpty else { throw ApiError.invalidPayload("Brak apilohelper_api w ustawieniach") }
        let path = "/polkoinator?profil=\(pathEsc(profil))&db=\(pathEsc(db))&polkaId=\(pathEsc(shelf))"
        let text = try await textRequest(URLRequest(url: try url(helper, path)), timeout: 15)
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.invalidPayload("Odpowiedź nie jest JSON-em")
        }
        return obj
    }

    // Lista kodów zdjęć części (/api/Magazyn/PobierzListeZdjecCzesci, header Id)
    static func photoList(api: String, db: String, login: String, password: String, partId: String) async throws -> [String] {
        if Dummy.on { return Dummy.photoList() }
        var req = URLRequest(url: try url(api, "/api/Magazyn/PobierzListeZdjecCzesci"))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(db, forHTTPHeaderField: "BazaDanych")
        req.setValue(login, forHTTPHeaderField: "Nazwa")
        req.setValue(password, forHTTPHeaderField: "Haslo")
        req.setValue(partId, forHTTPHeaderField: "Id")
        let obj = try await jsonRequest(req, timeout: 8)
        let dane = obj["dane"] as? [[String: Any]] ?? []
        return dane.compactMap { item in
            let k = ((item["kod"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            return k.isEmpty ? nil : k
        }
    }

    // MARK: - apilohelper (dodatki)

    // Mapowanie bazy -> profil: wyjątek z profileAliases albo nazwa bazy (lowercase)
    static func profile(_ db: String) -> String {
        let t = db.trimmingCharacters(in: .whitespaces)
        for (key, value) in profileAliases where t.caseInsensitiveCompare(key) == .orderedSame {
            return value
        }
        return t.lowercased()
    }

    private static func helperGet(_ helper: String, _ path: String) async throws -> String? {
        let text = try await textRequest(URLRequest(url: try url(helper, path)))
        return text.isEmpty ? nil : text.trimmingCharacters(in: .whitespaces)
    }

    static func factoryNumber(helper: String, profil: String, numer: String) async -> String? {
        if Dummy.on { return Dummy.factoryNumber() }
        guard !helper.isEmpty, !numer.isEmpty else { return nil }
        let p = pathEsc(profil), n = pathEsc(numer)
        guard let text = try? await helperGet(helper, "/darsoft-get-part-numer?profil=\(p)&numer=\(n)") else { return nil }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let out = (obj["numerFabryczny"] as? String)?.trimmingCharacters(in: .whitespaces),
              !out.isEmpty else { return nil }
        return out
    }

    static func partAddDate(helper: String, profil: String, sku: String) async -> String? {
        if Dummy.on { return Dummy.isoDate() }
        guard !helper.isEmpty, !sku.isEmpty else { return nil }
        return try? await helperGet(helper, "/darsoft-get-part-add-date?db=\(pathEsc(profil))&sku=\(pathEsc(sku))")
    }

    static func partPlaceDate(helper: String, profil: String, sku: String) async -> String? {
        if Dummy.on { return Dummy.isoDate() }
        guard !helper.isEmpty, !sku.isEmpty else { return nil }
        return try? await helperGet(helper, "/darsoft-get-part-place-date?db=\(pathEsc(profil))&sku=\(pathEsc(sku))")
    }

    // { maOpis, maNotatke }
    static func descAndNote(helper: String, profil: String, sku: String) async -> [String: Any]? {
        if Dummy.on { return ["maOpis": true, "maNotatke": true] }
        guard !helper.isEmpty, !sku.isEmpty else { return nil }
        guard let text = try? await helperGet(helper, "/darsoft-get-part-desc-and-note?profil=\(pathEsc(profil))&sku=\(pathEsc(sku))"),
              let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func partDesc(helper: String, profil: String, sku: String) async -> String? {
        if Dummy.on { return Dummy.desc() }
        guard !helper.isEmpty, !sku.isEmpty else { return nil }
        guard let text = try? await helperGet(helper, "/darsoft-get-part-desc?profil=\(pathEsc(profil))&sku=\(pathEsc(sku))"),
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let out = (obj["opis"] as? String)?.trimmingCharacters(in: .whitespaces),
              !out.isEmpty else { return nil }
        return out
    }

    static func partNote(helper: String, profil: String, sku: String) async -> String? {
        if Dummy.on { return Dummy.note() }
        guard !helper.isEmpty, !sku.isEmpty else { return nil }
        guard let text = try? await helperGet(helper, "/darsoft-get-part-note?profil=\(pathEsc(profil))&sku=\(pathEsc(sku))"),
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let out = (obj["notatka"] as? String)?.trimmingCharacters(in: .whitespaces),
              !out.isEmpty else { return nil }
        return out
    }

    static func updatePartNote(helper: String, profil: String, sku: String, note: String) async -> Bool {
        if Dummy.on { return true }
        guard !helper.isEmpty, !sku.isEmpty else { return false }
        // normalizacja do CRLF, jak na Androidzie
        let normalized = note
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        var req = URLRequest(url: try! url(helper, "/darsoft-update-part-note?profil=\(pathEsc(profil))&sku=\(pathEsc(sku))&notatka=\(pathEsc(normalized))"))
        req.httpMethod = "POST"
        req.httpBody = Data()
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let text = try? await textRequest(req),
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (obj["updated"] as? Bool) ?? false
    }

    private static func pathEsc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // MARK: - Formatowanie (jak w PartInfoUtils)

    static func formatLocation(_ raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        var s = raw
            .replacingOccurrences(of: "\\r\\n", with: "\\")
            .replacingOccurrences(of: "\r\n", with: "\\")
            .replacingOccurrences(of: "\n", with: "\\")
        while s.contains("\\\\") { s = s.replacingOccurrences(of: "\\\\", with: "\\") }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "\\/ "))
    }

    static func formatDateShort(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        if let d = f.date(from: iso) {
            f.dateFormat = "dd/MM/yyyy - HH:mm"
            return f.string(from: d)
        }
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = f.date(from: iso) {
            f.dateFormat = "dd/MM/yyyy - HH:mm"
            return f.string(from: d)
        }
        return iso.count >= 16 ? String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ") : iso
    }
}
