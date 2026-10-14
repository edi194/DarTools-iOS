import Foundation

struct User: Identifiable, Codable, Equatable {
    var name: String
    var password: String
    var allowedDbs: [String] = []

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, password
        case allowedDbs = "allowed_dbs"
    }

    init(name: String, password: String, allowedDbs: [String] = []) {
        self.name = name
        self.password = password
        self.allowedDbs = allowedDbs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        allowedDbs = try c.decodeIfPresent([String].self, forKey: .allowedDbs) ?? []
    }
}
