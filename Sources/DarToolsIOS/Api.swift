import Foundation
import Network

enum ApiError: LocalizedError {
    case transport(String)
    case badStatus(Int, String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .transport(let m): return m
        case .badStatus(let code, let body): return "HTTP \(code): \(body)"
        case .invalidPayload(let m): return m
        }
    }
}

enum Api {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 5
        return URLSession(configuration: c)
    }()

    private static func base(_ addr: String) -> String {
        let t = addr.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
        return "http://\(t)"
    }

    private static func url(_ addr: String, _ path: String) throws -> URL {
        let b = base(addr).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let u = URL(string: b + path) else { throw ApiError.invalidPayload("Nieprawidłowy adres API") }
        return u
    }

    private static func json(_ data: Data, _ response: URLResponse) throws -> [String: Any] {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ApiError.badStatus(http.statusCode, body)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.invalidPayload("Odpowiedź nie jest JSON-em")
        }
        return obj
    }

    // GET {api}/api/Ustawienia/Wersja
    static func fetchApiVersion(_ addr: String) async throws -> String {
        if Dummy.on { return "99.9.9" }
        let (data, resp) = try await session.data(for: URLRequest(url: try url(addr, "/api/Ustawienia/Wersja")))
        guard let dane = try json(data, resp)["dane"] as? [Any], let first = dane.first else {
            throw ApiError.invalidPayload("Brak danych w odpowiedzi")
        }
        return first as? String ?? "\(first)"
    }

    // GET {api}/api/Ustawienia/PobierzBazyDanych
    static func fetchDatabases(_ addr: String) async throws -> [String] {
        let (data, resp) = try await session.data(for: URLRequest(url: try url(addr, "/api/Ustawienia/PobierzBazyDanych")))
        let dane = try json(data, resp)["dane"] as? [Any] ?? []
        return dane.map { $0 as? String ?? "\($0)" }
    }

    // POST {api}/api/Uzytkownik/Zaloguj, headers: Nazwa / Haslo / BazaDanych
    static func loginUser(_ addr: String, login: String, password: String, db: String) async throws -> Bool {
        if Dummy.on { return true }
        var req = URLRequest(url: try url(addr, "/api/Uzytkownik/Zaloguj"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(login, forHTTPHeaderField: "Nazwa")
        req.setValue(password, forHTTPHeaderField: "Haslo")
        req.setValue(db, forHTTPHeaderField: "BazaDanych")
        req.httpBody = Data()
        let (data, resp) = try await session.data(for: req)
        let obj = try json(data, resp)
        let kod = obj["kod"] as? Int ?? -1
        let status = obj["status"] as? String ?? ""
        return kod == 200 && status.lowercased() == "success"
    }

    // Odkryj dozwolone bazy: test logowania do każdej z listy
    static func discoverAllowedDbs(_ addr: String, user: User) async -> [String] {
        if Dummy.on { return ["Baza Demo 1", "Baza Demo 2"] }
        guard let all = try? await fetchDatabases(addr) else { return [] }
        var out: [String] = []
        for db in all {
            if let ok = try? await loginUser(addr, login: user.name, password: user.password, db: db), ok {
                out.append(db)
            }
        }
        return out
    }
}

// Odpowiednik isNetworkAvailable() z Androida
@MainActor
final class NetworkStatus: ObservableObject {
    @Published var isOnline: Bool = true
    private let monitor = NWPathMonitor()

    static let shared = NetworkStatus()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "nwpath"))
    }
}
