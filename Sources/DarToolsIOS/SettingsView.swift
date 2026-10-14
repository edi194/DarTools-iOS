import SwiftUI

// Port SettingsScreen z SettingsActivity.kt
struct SettingsView: View {
    @State private var apiAddress = Prefs.apiAddress
    @State private var apilohelper = Prefs.apilohelperApi
    @State private var autoRefreshBraki = Prefs.autoRefreshBraki
    @State private var dummyMode = Prefs.dummyMode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Adres API") {
                    TextField("np. 192.168.1.10:8080 lub https://...", text: $apiAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Adres API apilohelper", text: $apilohelper)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Toggle("Auto-odświeżanie braków", isOn: $autoRefreshBraki)
                    Toggle("Tryb dummy", isOn: $dummyMode)
                } footer: {
                    Text("Auto-odświeżanie sprawdza braki co 5 minut, dopóki aplikacja jest otwarta, i wysyła powiadomienie. Tryb dummy podmienia dane z API na losowe — do zrzutów ekranu.")
                }
            }
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        Prefs.apiAddress = apiAddress.trimmingCharacters(in: .whitespaces)
                        Prefs.apilohelperApi = apilohelper.trimmingCharacters(in: .whitespaces)
                        Prefs.autoRefreshBraki = autoRefreshBraki
                        Prefs.dummyMode = dummyMode
                        if autoRefreshBraki { Notif.requestAuth() }
                        if dummyMode {
                            // wymagane przez guardy widoków ("Brak adresu API")
                            if Prefs.apiAddress.isEmpty { Prefs.apiAddress = "dummy.local" }
                            if Prefs.apilohelperApi.isEmpty { Prefs.apilohelperApi = "dummy.local" }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
