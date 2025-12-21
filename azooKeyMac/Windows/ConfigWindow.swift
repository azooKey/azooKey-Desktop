import Cocoa
import Core
import SwiftUI

struct ConfigWindow: View {
    @ConfigState private var liveConversion = Config.LiveConversion()
    @ConfigState private var inputStyle = Config.InputStyle()
    @ConfigState private var typeBackSlash = Config.TypeBackSlash()
    @ConfigState private var punctuationStyle = Config.PunctuationStyle()
    @ConfigState private var typeHalfSpace = Config.TypeHalfSpace()
    @ConfigState private var zenzaiProfile = Config.ZenzaiProfile()
    @ConfigState private var zenzaiPersonalizationLevel = Config.ZenzaiPersonalizationLevel()
    @ConfigState private var openAiApiKey = Config.OpenAiApiKey()
    @ConfigState private var openAiModelName = Config.OpenAiModelName()
    @ConfigState private var openAiApiEndpoint = Config.OpenAiApiEndpoint()
    @ConfigState private var learning = Config.Learning()
    @ConfigState private var inferenceLimit = Config.ZenzaiInferenceLimit()
    @ConfigState private var debugWindow = Config.DebugWindow()
    @ConfigState private var userDictionary = Config.UserDictionary()
    @ConfigState private var systemUserDictionary = Config.SystemUserDictionary()
    @ConfigState private var keyboardLayout = Config.KeyboardLayout()
    @ConfigState private var aiBackend = Config.AIBackendPreference()

    @State private var selectedTab: Tab = .input
    @State private var zenzaiProfileHelpPopover = false
    @State private var zenzaiInferenceLimitHelpPopover = false
    @State private var openAiApiKeyPopover = false
    @State private var connectionTestInProgress = false
    @State private var showingRomajiTableEditor = false
    @State private var connectionTestResult: String?
    @State private var systemUserDictionaryUpdateMessage: SystemUserDictionaryUpdateMessage?
    @State private var showingLearningResetConfirmation = false
    @State private var learningResetMessage: LearningResetMessage?
    @State private var foundationModelsAvailability: FoundationModelsAvailability?
    @State private var availabilityCheckDone = false

    enum Tab: String, CaseIterable {
        case input = "入力"
        case conversion = "変換"
        case ai = "AI機能"
        case dictionary = "辞書"
        case advanced = "詳細"

        var icon: String {
            switch self {
            case .input: return "keyboard"
            case .conversion: return "textformat"
            case .ai: return "sparkles"
            case .dictionary: return "book"
            case .advanced: return "gearshape"
            }
        }
    }

    private enum LearningResetMessage {
        case success
        case error(String)
    }

    private enum SystemUserDictionaryUpdateMessage {
        case error(any Error)
        case successfulUpdate
    }

    private func getErrorMessage(for error: OpenAIError) -> String {
        switch error {
        case .invalidURL:
            return "エラー: 無効なURL形式です"
        case .noServerResponse:
            return "エラー: サーバーから応答がありません"
        case .invalidResponseStatus(let code, let body):
            return getHTTPErrorMessage(code: code, body: body)
        case .parseError(let message):
            return "エラー: レスポンス解析失敗 - \(message)"
        case .invalidResponseStructure:
            return "エラー: 予期しないレスポンス形式"
        }
    }

    private func getHTTPErrorMessage(code: Int, body: String) -> String {
        switch code {
        case 401:
            return "エラー: APIキーが無効です"
        case 403:
            return "エラー: アクセスが拒否されました"
        case 404:
            return "エラー: エンドポイントが見つかりません"
        case 429:
            return "エラー: レート制限に達しました"
        case 500...599:
            return "エラー: サーバーエラー (コード: \(code))"
        default:
            return "エラー: HTTPステータス \(code)\n詳細: \(body.prefix(100))..."
        }
    }

    func testConnection() async {
        connectionTestInProgress = true
        connectionTestResult = nil

        do {
            let testRequest = OpenAIRequest(
                prompt: "テスト",
                target: "",
                modelName: openAiModelName.value.isEmpty ? Config.OpenAiModelName.default : openAiModelName.value
            )
            _ = try await OpenAIClient.sendRequest(
                testRequest,
                apiKey: openAiApiKey.value,
                apiEndpoint: openAiApiEndpoint.value
            )

            connectionTestResult = "接続成功"
        } catch let error as OpenAIError {
            connectionTestResult = getErrorMessage(for: error)
        } catch {
            connectionTestResult = "エラー: \(error.localizedDescription)"
        }

        connectionTestInProgress = false
    }

    @MainActor
    private func resetLearningData() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            learningResetMessage = .error("学習データのリセットに失敗しました")
            Task {
                try? await Task.sleep(for: .seconds(30))
                if case .error = learningResetMessage {
                    learningResetMessage = nil
                }
            }
            return
        }

        appDelegate.kanaKanjiConverter.resetMemory()
        learningResetMessage = .success

        // 10秒後にメッセージを消す
        Task {
            try? await Task.sleep(for: .seconds(10))
            if case .success = learningResetMessage {
                learningResetMessage = nil
            }
        }
    }

    @ViewBuilder
    private func helpButton(helpContent: LocalizedStringKey, isPresented: Binding<Bool>) -> some View {
        if #available(macOS 14, *) {
            Button("ヘルプ", systemImage: "questionmark") {
                isPresented.wrappedValue = true
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .popover(isPresented: isPresented) {
                Text(helpContent).padding()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            TabView(selection: $selectedTab) {
                inputTabView.tag(Tab.input)
                conversionTabView.tag(Tab.conversion)
                aiTabView.tag(Tab.ai)
                dictionaryTabView.tag(Tab.dictionary)
                advancedTabView.tag(Tab.advanced)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingRomajiTableEditor) {
            RomajiTableEditorWindow(base: CustomInputTableStore.loadTable()) { exported in
                do {
                    _ = try CustomInputTableStore.save(exported: exported)
                    CustomInputTableStore.registerIfExists()
                } catch {
                    print("Failed to save custom input table:", error)
                }
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("azooKey on macOS")
                .font(.title)
                .bold()
            Text("設定")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var inputTabView: some View {
        Form {
            Section {
                Picker("入力方式", selection: $inputStyle) {
                    Text("デフォルト").tag(Config.InputStyle.Value.default)
                    Text("かな入力（JIS）").tag(Config.InputStyle.Value.defaultKanaJIS)
                    Text("かな入力（US）").tag(Config.InputStyle.Value.defaultKanaUS)
                    Text("AZIK").tag(Config.InputStyle.Value.defaultAZIK)
                    Text("カスタム").tag(Config.InputStyle.Value.custom)
                }
                if inputStyle.value == .custom {
                    Button("カスタム入力テーブルを編集") {
                        showingRomajiTableEditor = true
                    }
                }
                Picker("キーボード配列", selection: $keyboardLayout) {
                    Text("QWERTY").tag(Config.KeyboardLayout.Value.qwerty)
                    Text("Colemak").tag(Config.KeyboardLayout.Value.colemak)
                    Text("Dvorak").tag(Config.KeyboardLayout.Value.dvorak)
                }
            } header: {
                Label("入力方式", systemImage: "keyboard")
            }

            Section {
                Toggle("ライブ変換を有効化", isOn: $liveConversion)
                Toggle("円記号の代わりにバックスラッシュを入力", isOn: $typeBackSlash)
                Toggle("スペースは常に半角を入力", isOn: $typeHalfSpace)
                Picker("句読点の種類", selection: $punctuationStyle) {
                    Text("、と。").tag(Config.PunctuationStyle.Value.`kutenAndToten`)
                    Text("、と．").tag(Config.PunctuationStyle.Value.periodAndToten)
                    Text("，と。").tag(Config.PunctuationStyle.Value.kutenAndComma)
                    Text("，と．").tag(Config.PunctuationStyle.Value.periodAndComma)
                }
            } header: {
                Label("入力オプション", systemImage: "character.cursor.ibeam")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tabItem {
            Label(Tab.input.rawValue, systemImage: Tab.input.icon)
        }
    }

    private var conversionTabView: some View {
        Form {
            Section {
                HStack {
                    TextField("変換プロフィール", text: $zenzaiProfile, prompt: Text("例：田中太郎/高校生"))
                    helpButton(
                        helpContent: """
                        Zenzaiはあなたのプロフィールを考慮した変換を行うことができます。
                        名前や仕事、趣味などを入力すると、それに合わせた変換が自動で推薦されます。
                        （実験的な機能のため、精度が不十分な場合があります）
                        """,
                        isPresented: $zenzaiProfileHelpPopover
                    )
                }
                HStack {
                    TextField(
                        "Zenzaiの推論上限",
                        text: Binding(
                            get: { String(self.$inferenceLimit.wrappedValue) },
                            set: {
                                if let value = Int($0), (1 ... 50).contains(value) {
                                    self.$inferenceLimit.wrappedValue = value
                                }
                            }
                        )
                    )
                    Stepper("", value: $inferenceLimit, in: 1 ... 50)
                        .labelsHidden()
                    helpButton(
                        helpContent: "推論上限を小さくすると、入力中のもたつきが改善されることがあります。",
                        isPresented: $zenzaiInferenceLimitHelpPopover
                    )
                }
            } header: {
                Label("Zenzai変換エンジン", systemImage: "brain")
            }

            Section {
                Picker("履歴学習", selection: $learning) {
                    Text("学習する").tag(Config.Learning.Value.inputAndOutput)
                    Text("学習を停止").tag(Config.Learning.Value.onlyOutput)
                    Text("学習を無視").tag(Config.Learning.Value.nothing)
                }
                LabeledContent {
                    HStack {
                        Button("リセット") {
                            showingLearningResetConfirmation = true
                        }
                        .confirmationDialog(
                            "履歴学習データをリセットしますか？",
                            isPresented: $showingLearningResetConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("リセット", role: .destructive) {
                                resetLearningData()
                            }
                            Button("キャンセル", role: .cancel) {}
                        }
                        Spacer()
                        switch learningResetMessage {
                        case .none:
                            EmptyView()
                        case .success:
                            Text("履歴学習データをリセットしました")
                                .foregroundColor(.green)
                        case .error(let message):
                            Text("エラー: \(message)")
                                .foregroundColor(.red)
                        }
                    }
                } label: {
                    Text("履歴学習データ")
                }
            } header: {
                Label("学習", systemImage: "memorychip")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tabItem {
            Label(Tab.conversion.rawValue, systemImage: Tab.conversion.icon)
        }
    }

    private var aiTabView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("いい感じ変換", selection: $aiBackend) {
                        Text("オフ").tag(Config.AIBackendPreference.Value.off)

                        if let availability = foundationModelsAvailability, availability.isAvailable {
                            Text("Foundation Models").tag(Config.AIBackendPreference.Value.foundationModels)
                        }

                        Text("OpenAI API").tag(Config.AIBackendPreference.Value.openAI)
                    }
                    .onAppear {
                        if !availabilityCheckDone {
                            foundationModelsAvailability = FoundationModelsClientCompat.checkAvailability()
                            availabilityCheckDone = true

                            let hasSetAIBackend = UserDefaults.standard.bool(forKey: "hasSetAIBackendManually")
                            if !hasSetAIBackend,
                               aiBackend.value == .off,
                               let availability = foundationModelsAvailability,
                               availability.isAvailable {
                                aiBackend.value = .foundationModels
                                UserDefaults.standard.set(true, forKey: "hasSetAIBackendManually")
                            }

                            if aiBackend.value == .foundationModels,
                               let availability = foundationModelsAvailability,
                               !availability.isAvailable {
                                aiBackend.value = .off
                            }
                        }
                    }
                    .onChange(of: aiBackend.value) { _ in
                        UserDefaults.standard.set(true, forKey: "hasSetAIBackendManually")
                    }

                    if aiBackend.value == .openAI {
                        Divider()
                        openAISettingsView
                    }
                }
            } header: {
                Label("AI変換設定", systemImage: "sparkles")
            } footer: {
                if aiBackend.value == .foundationModels {
                    Text("Foundation ModelsはローカルのApple Intelligenceを使用します。API課金は発生しません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if aiBackend.value == .openAI {
                    Text("OpenAI APIを使用すると課金が発生します。APIキーはローカルにのみ保存されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tabItem {
            Label(Tab.ai.rawValue, systemImage: Tab.ai.icon)
        }
    }

    private var openAISettingsView: some View {
        Group {
            HStack {
                SecureField("APIキー", text: $openAiApiKey, prompt: Text("例:sk-xxxxxxxxxxx"))
                helpButton(
                    helpContent: "OpenAI APIキーはローカルのみで管理され、外部に公開されることはありません。生成の際にAPIを利用するため、課金が発生します。",
                    isPresented: $openAiApiKeyPopover
                )
            }
            TextField("モデル名", text: $openAiModelName, prompt: Text("例: gpt-4o-mini"))
            TextField("エンドポイント", text: $openAiApiEndpoint, prompt: Text("例: https://api.openai.com/v1/chat/completions"))
                .help("例: https://api.openai.com/v1/chat/completions\nGemini: https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")

            HStack {
                Button("接続テスト") {
                    Task {
                        await testConnection()
                    }
                }
                .disabled(connectionTestInProgress || openAiApiKey.value.isEmpty)

                if connectionTestInProgress {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if let result = connectionTestResult {
                Text(result)
                    .foregroundColor(result.contains("成功") ? .green : .red)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dictionaryTabView: some View {
        Form {
            Section {
                LabeledContent {
                    HStack {
                        Button("編集") {
                            (NSApplication.shared.delegate as? AppDelegate)!.openUserDictionaryEditorWindow()
                        }
                        Spacer()
                        Text("\(self.userDictionary.value.items.count)件のアイテム")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("azooKeyユーザ辞書")
                }
            } header: {
                Label("ユーザ辞書", systemImage: "book.closed")
            }

            Section {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            Button("読み込む") {
                                do {
                                    let systemUserDictionaryEntries = try SystemUserDictionaryHelper.fetchEntries()
                                    self.systemUserDictionary.value.items = systemUserDictionaryEntries.map {
                                        .init(word: $0.phrase, reading: $0.shortcut)
                                    }
                                    self.systemUserDictionary.value.lastUpdate = .now
                                    self.systemUserDictionaryUpdateMessage = .successfulUpdate
                                } catch {
                                    self.systemUserDictionaryUpdateMessage = .error(error)
                                }
                            }
                            Button("リセット") {
                                self.systemUserDictionary.value.lastUpdate = nil
                                self.systemUserDictionary.value.items = []
                                self.systemUserDictionaryUpdateMessage = nil
                            }
                        }
                        switch self.systemUserDictionaryUpdateMessage {
                        case .none:
                            if let updated = self.systemUserDictionary.value.lastUpdate {
                                Text("最終更新: \(updated.formatted()) / \(self.systemUserDictionary.value.items.count)件のアイテム")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("未設定")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .error(let error):
                            Text("読み込みエラー: \(error.localizedDescription)")
                                .font(.caption)
                                .foregroundColor(.red)
                        case .successfulUpdate:
                            Text("読み込みに成功しました / \(self.systemUserDictionary.value.items.count)件のアイテム")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                } label: {
                    Text("システムのユーザ辞書")
                }
            } header: {
                Label("システム辞書", systemImage: "folder")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tabItem {
            Label(Tab.dictionary.rawValue, systemImage: Tab.dictionary.icon)
        }
    }

    private var advancedTabView: some View {
        Form {
            Section {
                Toggle("デバッグウィンドウを有効化", isOn: $debugWindow)
                Picker("パーソナライズ", selection: $zenzaiPersonalizationLevel) {
                    Text("オフ").tag(Config.ZenzaiPersonalizationLevel.Value.off)
                    Text("弱く").tag(Config.ZenzaiPersonalizationLevel.Value.soft)
                    Text("普通").tag(Config.ZenzaiPersonalizationLevel.Value.normal)
                    Text("強く").tag(Config.ZenzaiPersonalizationLevel.Value.hard)
                }
            } header: {
                Label("開発者向け設定", systemImage: "hammer")
            }

            Section {
                LabeledContent("Version") {
                    Text(PackageMetadata.gitTag ?? PackageMetadata.gitCommit ?? "Unknown Version")
                        .monospaced()
                        .bold()
                        .copyable([
                            PackageMetadata.gitTag ?? PackageMetadata.gitCommit ?? "Unknown Version"
                        ])
                }
            } header: {
                Label("アプリ情報", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tabItem {
            Label(Tab.advanced.rawValue, systemImage: Tab.advanced.icon)
        }
    }
}

#Preview {
    ConfigWindow()
}
