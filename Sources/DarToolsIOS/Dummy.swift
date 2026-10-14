import Foundation
import UIKit

// Tryb dummy (Ustawienia → „Tryb dummy"): wszystkie wywołania API zastępowane
// losowymi danymi — do zrzutów ekranu i testów bez serwera.
enum Dummy {
    static var on: Bool { Prefs.dummyMode }

    // MARK: - Słowniki
    private static let brands = ["Bosch", "Valeo", "Sachs", "Lemförder", "Febi Bilstein", "Mann-Filter", "NGK", "Denso", "Hella", "TRW"]
    private static let parts = ["Klocki hamulcowe przód", "Tarcza hamulcowa wentylowana", "Filtr oleju", "Filtr powietrza", "Amortyzator tylny", "Zestaw rozrządu", "Pompa wody", "Świece zapłonowe", "Akumulator 74Ah", "Wtryskiwacz CR", "Sonda lambda", "Termostat", "Chłodnica silnika", "Alternator 140A", "Rozrusznik", "Sprężyna zawieszenia", "Łożysko koła", "Półos napędowa"]
    private static let vehicles = ["Audi A4 B8", "VW Passat B7", "BMW 320d F30", "Opel Astra J", "Toyota Corolla E210", "Ford Focus III", "Skoda Octavia III", "Renault Megane IV", "Kia Ceed III", "Hyundai i30"]
    private static let platforms = ["allegro", "ovoko", "sms"]
    private static let locations = [
        "Hala antresola \\ Poziom 1 \\ Rząd 3 \\ Regał 7 \\ Półka 12",
        "Hala antresola \\ Poziom 2 \\ Rząd 1 \\ Regał 2 \\ Półka 5",
        "Magazyn główny \\ Sekcja B \\ Regał 14",
        "Strefa wysyłki \\ Box 3",
        ""
    ]
    private static let descSentences = [
        "Część z demontażu, stan bardzo dobry.",
        "Bez śladów korozji i uszkodzeń mechanicznych.",
        "Przeglądana przez mechanika, gotowa do montażu.",
        "Kompatybilna z rocznikami 2014–2020.",
        "Gwarancja rozruchowa 30 dni."
    ]

    // MARK: - Pomocnicze
    private static func digits(_ n: Int) -> String {
        String((0..<n).compactMap { _ in "0123456789".randomElement() })
    }

    static func isoDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let d = Date().addingTimeInterval(-TimeInterval.random(in: 0...(90 * 86400)))
        return f.string(from: d)
    }

    // MARK: - Magazyn (API bazowe)
    static func part(code: String) -> [String: Any] {
        [
            "id": digits(6),
            "kodKreskowy": code.isEmpty ? digits(13) : code,
            "nazwa": "\(parts.randomElement()!) \(brands.randomElement()!)",
            "lokalizacja": locations.randomElement()!,
            "marka": brands.randomElement()!,
            "model": vehicles.randomElement()!,
            "magazyn_IloscSztuk": Int.random(in: 1...24),
            "cena": Double(Int.random(in: 1599...45999)) / 100.0,
            "podstawoweZdjecie": "dummy-" + digits(8)
        ]
    }

    static func shelf() -> [[String: Any]] {
        (0..<Int.random(in: 3...8)).map { _ in part(code: digits(13)) }
    }

    static func photoList() -> [String] {
        (0..<Int.random(in: 2...5)).map { "dummy-photo-\($0)" }
    }

    // placeholder: kolorowy kafelek zależny od uuid (siatka zdjęć wygląda realnie)
    static func photo(uuid: String) -> Data? {
        let hue = CGFloat(uuid.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 }) / 360.0
        let size = CGSize(width: 640, height: 480)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(hue: hue, saturation: 0.22, brightness: 0.94, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(hue: hue, saturation: 0.42, brightness: 0.62, alpha: 1).setFill()
            ctx.fill(CGRect(x: size.width * 0.22, y: size.height * 0.24, width: size.width * 0.56, height: size.height * 0.52))
        }
        return img.pngData()
    }

    // MARK: - apilohelper
    static func factoryNumber() -> String { "W0" + digits(8) }

    static func note() -> String {
        ["Klient prosił o kontakt przed wysyłką.",
         "Towar zarezerwowany do piątku.",
         "Wysyłka kurierem, paczka 30 kg."].randomElement()!
    }

    static func desc() -> String {
        (0..<Int.random(in: 2...4)).compactMap { _ in descSentences.randomElement() }.joined(separator: " ")
    }

    // MARK: - Zamówienia (apilo / baselinker / dt_mobile)
    static func orderItems() -> [OrderItem] {
        (0..<Int.random(in: 8...16)).map { _ in
            OrderItem([
                "sku": digits(13),
                "apiloOrderId": digits(7),
                "platformName": platforms.randomElement()!,
                "quantity": Int.random(in: 1...4),
                "nazwa": "\(parts.randomElement()!) \(brands.randomElement()!)",
                "markaPojazdu": vehicles.randomElement()!,
                "lokalizacja": locations.randomElement()!,
                "kosztWysylki": Double(Int.random(in: 500...2500)) / 100.0,
                "datazamowienia": isoDate(),
                "baselinker": Bool.random(),
                "statusId": 42
            ])
        }
    }

    private static func skus() -> [[String: Any]] {
        (0..<Int.random(in: 1...3)).map { _ in ["sku": digits(13), "quantity": Int.random(in: 1...3)] }
    }

    static func apiloOrders() -> [[String: Any]] {
        (0..<Int.random(in: 3...6)).map { _ in
            ["apiloOrderId": digits(7),
             "platformName": platforms.randomElement()!,
             "skus": skus()]
        }
    }

    static func baselinkerOrders() -> [[String: Any]] {
        (0..<Int.random(in: 2...5)).map { _ in
            ["orderNumber": "BL" + digits(6),
             "platformName": platforms.randomElement()!,
             "notatka": note(),
             "skus": skus()]
        }
    }
}
