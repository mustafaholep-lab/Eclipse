import SwiftUI

struct SubtitleTranslationSettingsView: View {
    @State private var mode = SubtitleTranslationMode.off
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var preservesHonorifics = true
    @State private var testing = false
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                Picker("AI çeviri", selection: $mode) {
                    ForEach(SubtitleTranslationMode.allCases, id: \.rawValue) { item in
                        Text(item.title).tag(item)
                    }
                }
                .onChange(of: mode) { value in SubtitleTranslationSettings.mode = value }
                Toggle("Japonca hitap eklerini koru", isOn: $preservesHonorifics)
                    .onChange(of: preservesHonorifics) { value in SubtitleTranslationSettings.preservesHonorifics = value }
            } footer: {
                Text("Altyazı metni, yapılandırdığınız çeviri API'sine gönderilir. Sor modunda siz başlatmadan metin gönderilmez.")
            }

            Section("OpenAI-compatible Chat Completions") {
                TextField("Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: baseURL) { value in SubtitleTranslationSettings.baseURL = value }
                TextField("Model", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: model) { value in SubtitleTranslationSettings.model = value }
                SecureField(hasSavedKey ? "API anahtarı kayıtlı · değiştirmek için girin" : "API anahtarı", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                Button("API anahtarını kaydet") { saveKey() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasSavedKey {
                    Button("API anahtarını kaldır", role: .destructive) {
                        SubtitleProviderCredentialStore.delete(SubtitleTranslationSettings.keyAccount)
                        hasSavedKey = false
                        apiKey = ""
                        status = String(localized: "API anahtarı kaldırıldı.")
                    }
                }
                Button(testing ? "Bağlantı sınanıyor…" : "Bağlantıyı Sına") {
                    Task { await testConnection() }
                }
                .disabled(testing)
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }

            Section {
                Button("AI çeviri önbelleğini temizle", role: .destructive) {
                    Task {
                        await DiskSubtitleTranslationCache.shared.clear()
                        status = String(localized: "AI çeviri önbelleği temizlendi.")
                    }
                }
            }
        }
        .navigationTitle("Türkçe AI Altyazı")
        .onAppear {
            mode = SubtitleTranslationSettings.mode
            baseURL = SubtitleTranslationSettings.baseURL
            model = SubtitleTranslationSettings.model
            preservesHonorifics = SubtitleTranslationSettings.preservesHonorifics
            hasSavedKey = SubtitleTranslationSettings.hasKey
        }
    }

    private func saveKey() {
        do {
            try SubtitleProviderCredentialStore.save(apiKey, account: SubtitleTranslationSettings.keyAccount)
            hasSavedKey = true
            apiKey = ""
            status = String(localized: "API anahtarı Keychain'e kaydedildi.")
        } catch {
            status = String(localized: "API anahtarı kaydedilemedi.")
        }
    }

    private func testConnection() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SubtitleProviderCredentialStore.value(SubtitleTranslationSettings.keyAccount)
            : apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else { status = SubtitleTranslationError.missingKey.localizedDescription; return }
        testing = true
        defer { testing = false }
        do {
            try await OpenAICompatibleTranslationProvider(baseURL: baseURL, apiKey: key, model: model).testConnection()
            status = String(localized: "Bağlantı doğrulandı.")
        } catch let error as SubtitleTranslationError {
            status = error.localizedDescription
        } catch {
            status = SubtitleTranslationError.connection.localizedDescription
        }
    }
}
