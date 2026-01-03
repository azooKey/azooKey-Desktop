import Cocoa
import Core
import KanaKanjiConverterModule
import SwiftUI

struct ConfigWindow: View {
    @State private var selectedTab: Tab = .basic
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
    @State private var initialLoadDone = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var cachedCustomInputTable: InputTable?
    @State private var cachedUserDictCount: Int?
    @State private var cachedSystemDictCount: Int?
    @State private var cachedSystemDictLastUpdate: Date?
    @State private var cachedAIBackend: Config.AIBackendPreference.Value?
    @State private var cachedZenzaiProfile: String?
    @State private var cachedLiveConversion: Bool?
    @State private var cachedInputStyle: Config.InputStyle.Value?
    @State private var cachedTypeBackSlash: Bool?
    @State private var cachedTypeHalfSpace: Bool?
    @State private var cachedPunctuationStyle: Config.PunctuationStyle.Value?
    @State private var cachedLearning: Config.Learning.Value?
    @State private var cachedOpenAiApiKey: String?
    @State private var cachedOpenAiModelName: String?
    @State private var cachedOpenAiApiEndpoint: String?
    @State private var cachedInferenceLimit: Int?
    @State private var cachedZenzaiPersonalizationLevel: Config.ZenzaiPersonalizationLevel.Value?
    @State private var cachedKeyboardLayout: Config.KeyboardLayout.Value?
    @State private var cachedDebugWindow: Bool?

    enum Tab: String, CaseIterable, Hashable {
        case basic = "基本"
        case customize = "カスタマイズ"
        case advanced = "詳細設定"

        var icon: String {
            switch self {
            case .basic: return "star"
            case .customize: return "slider.horizontal.3"
            case .advanced: return "gearshape.2"
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

    private struct DictionaryInfo {
        let userDict: Int
        let systemDict: Int
        let systemLastUpdate: Date?
    }

    // @ConfigStateを経由せずに直接UserDefaultsから辞書データを読み込むヘルパー関数
    nonisolated private static func loadDictionaryInfo() -> DictionaryInfo {
        var userCount = 0
        var systemCount = 0
        var systemLastUpdate: Date?

        // ユーザ辞書のカウント
        if let data = UserDefaults.standard.data(forKey: Config.UserDictionary.key),
           let dict = try? JSONDecoder().decode(Config.UserDictionary.Value.self, from: data) {
            userCount = dict.items.count
        }

        // システム辞書のカウントと最終更新日時
        if let data = UserDefaults.standard.data(forKey: Config.SystemUserDictionary.key),
           let dict = try? JSONDecoder().decode(Config.SystemUserDictionary.Value.self, from: data) {
            systemCount = dict.items.count
            systemLastUpdate = dict.lastUpdate
        }

        return DictionaryInfo(
            userDict: userCount,
            systemDict: systemCount,
            systemLastUpdate: systemLastUpdate
        )
    }

    // システムユーザ辞書を直接UserDefaultsに保存するヘルパー関数（@ConfigStateを経由しない）
    private static func saveSystemUserDictionary(items: [Config.UserDictionaryEntry], lastUpdate: Date?) {
        let value = Config.SystemUserDictionary.Value(lastUpdate: lastUpdate, items: items)
        if let encoded = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(encoded, forKey: Config.SystemUserDictionary.key)
        }
    }

    private struct AllConfigs {
        let zenzaiProfile: String
        let liveConversion: Bool
        let inputStyle: Config.InputStyle.Value
        let typeBackSlash: Bool
        let typeHalfSpace: Bool
        let punctuationStyle: Config.PunctuationStyle.Value
        let learning: Config.Learning.Value
        let openAiApiKey: String
        let openAiModelName: String
        let openAiApiEndpoint: String
        let inferenceLimit: Int
        let zenzaiPersonalizationLevel: Config.ZenzaiPersonalizationLevel.Value
        let keyboardLayout: Config.KeyboardLayout.Value
        let debugWindow: Bool
    }

    // 全ての設定値をバックグラウンドで読み込む
    nonisolated private static func loadAllConfigs() async -> AllConfigs {
        let zenzaiProfile = UserDefaults.standard.string(forKey: Config.ZenzaiProfile.key) ?? ""
        let liveConversion = UserDefaults.standard.bool(forKey: Config.LiveConversion.key)

        let inputStyle: Config.InputStyle.Value
        if let data = UserDefaults.standard.data(forKey: Config.InputStyle.key),
           let decoded = try? JSONDecoder().decode(Config.InputStyle.Value.self, from: data) {
            inputStyle = decoded
        } else {
            inputStyle = Config.InputStyle.default
        }

        let typeBackSlash = UserDefaults.standard.bool(forKey: Config.TypeBackSlash.key)
        let typeHalfSpace = UserDefaults.standard.bool(forKey: Config.TypeHalfSpace.key)

        let punctuationStyle: Config.PunctuationStyle.Value
        if let data = UserDefaults.standard.data(forKey: Config.PunctuationStyle.key),
           let decoded = try? JSONDecoder().decode(Config.PunctuationStyle.Value.self, from: data) {
            punctuationStyle = decoded
        } else {
            punctuationStyle = Config.PunctuationStyle.default
        }

        let learning: Config.Learning.Value
        if let data = UserDefaults.standard.data(forKey: Config.Learning.key),
           let decoded = try? JSONDecoder().decode(Config.Learning.Value.self, from: data) {
            learning = decoded
        } else {
            learning = Config.Learning.default
        }

        // OpenAI設定の読み込み（Keychainから非同期）
        let openAiApiKey = await KeychainHelper.read(key: Config.OpenAiApiKey.key) ?? ""
        let openAiModelName = UserDefaults.standard.string(forKey: Config.OpenAiModelName.key) ?? Config.OpenAiModelName.default
        let openAiApiEndpoint = UserDefaults.standard.string(forKey: Config.OpenAiApiEndpoint.key) ?? Config.OpenAiApiEndpoint.default

        // 詳細設定タブの設定
        let inferenceLimit = UserDefaults.standard.integer(forKey: Config.ZenzaiInferenceLimit.key)
        let finalInferenceLimit = (1...50).contains(inferenceLimit) ? inferenceLimit : Config.ZenzaiInferenceLimit.default

        let zenzaiPersonalizationLevel: Config.ZenzaiPersonalizationLevel.Value
        if let data = UserDefaults.standard.data(forKey: Config.ZenzaiPersonalizationLevel.key),
           let decoded = try? JSONDecoder().decode(Config.ZenzaiPersonalizationLevel.Value.self, from: data) {
            zenzaiPersonalizationLevel = decoded
        } else {
            zenzaiPersonalizationLevel = Config.ZenzaiPersonalizationLevel.default
        }

        let keyboardLayout: Config.KeyboardLayout.Value
        if let data = UserDefaults.standard.data(forKey: Config.KeyboardLayout.key),
           let decoded = try? JSONDecoder().decode(Config.KeyboardLayout.Value.self, from: data) {
            keyboardLayout = decoded
        } else {
            keyboardLayout = Config.KeyboardLayout.default
        }

        let debugWindow = UserDefaults.standard.bool(forKey: Config.DebugWindow.key)

        return AllConfigs(
            zenzaiProfile: zenzaiProfile,
            liveConversion: liveConversion,
            inputStyle: inputStyle,
            typeBackSlash: typeBackSlash,
            typeHalfSpace: typeHalfSpace,
            punctuationStyle: punctuationStyle,
            learning: learning,
            openAiApiKey: openAiApiKey,
            openAiModelName: openAiModelName,
            openAiApiEndpoint: openAiApiEndpoint,
            inferenceLimit: finalInferenceLimit,
            zenzaiPersonalizationLevel: zenzaiPersonalizationLevel,
            keyboardLayout: keyboardLayout,
            debugWindow: debugWindow
        )
    }

    func testConnection() async {
        connectionTestInProgress = true
        connectionTestResult = nil

        do {
            let modelName = cachedOpenAiModelName ?? Config.OpenAiModelName.default
            let apiKey = cachedOpenAiApiKey ?? ""
            let apiEndpoint = cachedOpenAiApiEndpoint ?? Config.OpenAiApiEndpoint.default

            let testRequest = OpenAIRequest(
                prompt: "テスト",
                target: "",
                modelName: modelName.isEmpty ? Config.OpenAiModelName.default : modelName
            )
            _ = try await OpenAIClient.sendRequest(
                testRequest,
                apiKey: apiKey,
                apiEndpoint: apiEndpoint
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
        // SwiftUIのTabViewを使用せず独自実装にした理由:
        // TabViewはタブ切り替え時に内部的に全てのタブビューを事前レンダリングしようとするため、
        // メインスレッドがブロックされレインボーカーソル（ビーチボール）が発生していた。
        // 独自実装により、選択されたタブのみをレンダリングすることで問題を解決。
        VStack(spacing: 0) {
            // カスタムタブバー（いい感じ変換ウィンドウ風の角丸デザイン）
            HStack(spacing: 4) {
                ForEach([Tab.basic, Tab.customize, Tab.advanced], id: \.self) { tab in
                    Button(
                        action: {
                            selectedTab = tab
                        },
                        label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selectedTab == tab ? Color(nsColor: .controlAccentColor) : Color(nsColor: .secondaryLabelColor))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: selectedTab == tab ? .medium : .regular))
                                    .foregroundColor(selectedTab == tab ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        selectedTab == tab ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                                        lineWidth: 0.5
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.3))
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // コンテンツエリア（選択されたタブのみ表示）
            Group {
                if selectedTab == .basic {
                    basicTabView
                } else if selectedTab == .customize {
                    customizeTabView
                } else {
                    advancedTabView
                }
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            performInitialLoad()
        }
        .onDisappear {
            // ウィンドウが閉じられる時に実行中のタスクをキャンセル
            loadingTask?.cancel()
        }
        .sheet(isPresented: $showingRomajiTableEditor) {
            // キャッシュされたテーブルを使用（ビュー再評価のたびにloadTable()が実行されるのを防ぐ）
            RomajiTableEditorWindow(base: cachedCustomInputTable) { exported in
                do {
                    _ = try CustomInputTableStore.save(exported: exported)
                    CustomInputTableStore.registerIfExists()
                    // 保存後にキャッシュを更新
                    cachedCustomInputTable = CustomInputTableStore.loadTable()
                } catch {
                    print("Failed to save custom input table: \(error)")
                }
            }
        }
        .onChange(of: showingRomajiTableEditor) { isShowing in
            // エディタを開く直前にテーブルを読み込む
            if isShowing {
                cachedCustomInputTable = CustomInputTableStore.loadTable()
            }
        }
    }

    private func performInitialLoad() {
        // 既に読み込み済みまたは読み込み中の場合はスキップ
        guard !initialLoadDone, loadingTask == nil else {
            return
        }
        initialLoadDone = true

        // Foundation Models可用性チェック（初回のみ実行、キャッシュする）
        if foundationModelsAvailability == nil {
            foundationModelsAvailability = FoundationModelsClientCompat.checkAvailability()
        }

        // 重い処理を単一のタスクで実行（タブ切り替えで再実行されない）
        loadingTask = Task { @MainActor in
            // バックグラウンドで全ての設定を並行読み込み
            async let dictInfo = Task.detached(priority: .userInitiated) {
                ConfigWindow.loadDictionaryInfo()
            }.value

            async let configs = Task.detached(priority: .userInitiated) {
                await ConfigWindow.loadAllConfigs()
            }.value

            async let aiBackend = Task.detached(priority: .userInitiated) { () -> Config.AIBackendPreference.Value in
                let currentBackend: Config.AIBackendPreference.Value
                if let data = UserDefaults.standard.data(forKey: Config.AIBackendPreference.key),
                   let decoded = try? JSONDecoder().decode(Config.AIBackendPreference.Value.self, from: data) {
                    currentBackend = decoded
                } else {
                    currentBackend = Config.AIBackendPreference.default
                }
                return currentBackend
            }.value

            // 全ての読み込みを待機
            let (loadedDictInfo, loadedConfigs, loadedAIBackend) = await (dictInfo, configs, aiBackend)

            // タスクがキャンセルされていないか確認
            guard !Task.isCancelled else {
                return
            }

            // AIBackendの自動設定（必要な場合のみ）
            let hasSetAIBackend = UserDefaults.standard.bool(forKey: "hasSetAIBackendManually")
            var finalBackend = loadedAIBackend

            if !hasSetAIBackend,
               loadedAIBackend == .off,
               let availability = foundationModelsAvailability,
               availability.isAvailable {
                finalBackend = .foundationModels
                if let encoded = try? JSONEncoder().encode(Config.AIBackendPreference.Value.foundationModels) {
                    UserDefaults.standard.set(encoded, forKey: Config.AIBackendPreference.key)
                }
                UserDefaults.standard.set(true, forKey: "hasSetAIBackendManually")
            } else if loadedAIBackend == .foundationModels,
                      let availability = foundationModelsAvailability,
                      !availability.isAvailable {
                finalBackend = .off
                if let encoded = try? JSONEncoder().encode(Config.AIBackendPreference.Value.off) {
                    UserDefaults.standard.set(encoded, forKey: Config.AIBackendPreference.key)
                }
            }

            // 全てのキャッシュを一度に更新
            self.cachedUserDictCount = loadedDictInfo.userDict
            self.cachedSystemDictCount = loadedDictInfo.systemDict
            self.cachedSystemDictLastUpdate = loadedDictInfo.systemLastUpdate
            self.cachedAIBackend = finalBackend
            self.cachedZenzaiProfile = loadedConfigs.zenzaiProfile
            self.cachedLiveConversion = loadedConfigs.liveConversion
            self.cachedInputStyle = loadedConfigs.inputStyle
            self.cachedTypeBackSlash = loadedConfigs.typeBackSlash
            self.cachedTypeHalfSpace = loadedConfigs.typeHalfSpace
            self.cachedPunctuationStyle = loadedConfigs.punctuationStyle
            self.cachedLearning = loadedConfigs.learning
            self.cachedOpenAiApiKey = loadedConfigs.openAiApiKey
            self.cachedOpenAiModelName = loadedConfigs.openAiModelName
            self.cachedOpenAiApiEndpoint = loadedConfigs.openAiApiEndpoint
            self.cachedInferenceLimit = loadedConfigs.inferenceLimit
            self.cachedZenzaiPersonalizationLevel = loadedConfigs.zenzaiPersonalizationLevel
            self.cachedKeyboardLayout = loadedConfigs.keyboardLayout
            self.cachedDebugWindow = loadedConfigs.debugWindow

            // タスクの完了を記録
            self.loadingTask = nil
        }
    }

    // MARK: - 基本タブ
    @ViewBuilder
    private var basicTabView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("いい感じ変換", selection: Binding(
                        get: { cachedAIBackend ?? .off },
                        set: { newValue in
                            cachedAIBackend = newValue
                            // UserDefaultsに非同期で保存（メインスレッドをブロックしない）
                            Task.detached(priority: .userInitiated) {
                                if let encoded = try? JSONEncoder().encode(newValue) {
                                    UserDefaults.standard.set(encoded, forKey: Config.AIBackendPreference.key)
                                }
                                UserDefaults.standard.set(true, forKey: "hasSetAIBackendManually")
                            }
                        }
                    )) {
                        Text("オフ").tag(Config.AIBackendPreference.Value.off)

                        if let availability = foundationModelsAvailability, availability.isAvailable {
                            Text("Foundation Models").tag(Config.AIBackendPreference.Value.foundationModels)
                        }

                        Text("OpenAI API").tag(Config.AIBackendPreference.Value.openAI)
                    }

                    // OpenAI API選択時は設定を展開表示
                    if cachedAIBackend == .openAI {
                        Divider()

                        HStack {
                            SecureField("APIキー", text: Binding(
                                get: { cachedOpenAiApiKey ?? "" },
                                set: { newValue in
                                    cachedOpenAiApiKey = newValue
                                    // Keychainに直接保存（非同期）
                                    Task {
                                        await KeychainHelper.save(key: Config.OpenAiApiKey.key, value: newValue)
                                    }
                                }
                            ), prompt: Text("例:sk-xxxxxxxxxxx"))
                            helpButton(
                                helpContent: "OpenAI APIキーはローカルのみで管理され、外部に公開されることはありません。生成の際にAPIを利用するため、課金が発生します。",
                                isPresented: $openAiApiKeyPopover
                            )
                        }

                        TextField("モデル名", text: Binding(
                            get: { cachedOpenAiModelName ?? Config.OpenAiModelName.default },
                            set: { newValue in
                                cachedOpenAiModelName = newValue
                                // UserDefaultsに直接保存（@ConfigStateを経由しない）
                                UserDefaults.standard.set(newValue, forKey: Config.OpenAiModelName.key)
                            }
                        ), prompt: Text("例: gpt-4o-mini"))

                        TextField("エンドポイント", text: Binding(
                            get: { cachedOpenAiApiEndpoint ?? Config.OpenAiApiEndpoint.default },
                            set: { newValue in
                                cachedOpenAiApiEndpoint = newValue
                                // UserDefaultsに直接保存（@ConfigStateを経由しない）
                                UserDefaults.standard.set(newValue, forKey: Config.OpenAiApiEndpoint.key)
                            }
                        ), prompt: Text("例: https://api.openai.com/v1/chat/completions"))
                        .help("例: https://api.openai.com/v1/chat/completions\nGemini: https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")

                        HStack {
                            Button("接続テスト") {
                                Task {
                                    await testConnection()
                                }
                            }
                            .disabled(connectionTestInProgress || (cachedOpenAiApiKey ?? "").isEmpty)

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
            } header: {
                Label("いい感じ変換", systemImage: "sparkles")
            } footer: {
                if let backend = cachedAIBackend {
                    if backend == .foundationModels {
                        Text("Foundation ModelsはローカルのApple Intelligenceを使用します。API課金は発生しません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if backend == .openAI {
                        Text("OpenAI APIを使用すると課金が発生します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent {
                    HStack {
                        if let count = cachedUserDictCount {
                            Text("\(count)件のアイテム")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Spacer()
                        Button("編集") {
                            (NSApplication.shared.delegate as? AppDelegate)!.openUserDictionaryEditorWindow()
                        }
                    }
                } label: {
                    Text("azooKeyユーザ辞書")
                }

                LabeledContent {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            Button("読み込む") {
                                Task {
                                    do {
                                        let systemUserDictionaryEntries = try SystemUserDictionaryHelper.fetchEntries()
                                        let items = systemUserDictionaryEntries.map {
                                            Config.UserDictionaryEntry(word: $0.phrase, reading: $0.shortcut)
                                        }
                                        let now = Date.now
                                        ConfigWindow.saveSystemUserDictionary(items: items, lastUpdate: now)
                                        self.systemUserDictionaryUpdateMessage = .successfulUpdate
                                        self.cachedSystemDictCount = items.count
                                        self.cachedSystemDictLastUpdate = now
                                    } catch {
                                        self.systemUserDictionaryUpdateMessage = .error(error)
                                    }
                                }
                            }
                            Button("リセット") {
                                ConfigWindow.saveSystemUserDictionary(items: [], lastUpdate: nil)
                                self.systemUserDictionaryUpdateMessage = nil
                                self.cachedSystemDictCount = 0
                                self.cachedSystemDictLastUpdate = nil
                            }
                        }
                        switch self.systemUserDictionaryUpdateMessage {
                        case .none:
                            if let updated = cachedSystemDictLastUpdate {
                                if let count = cachedSystemDictCount {
                                    Text("最終更新: \(updated.formatted()) / \(count)件のアイテム")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
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
                            if let count = cachedSystemDictCount {
                                Text("読み込みに成功しました / \(count)件のアイテム")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                } label: {
                    Text("システムのユーザ辞書")
                }
            } header: {
                Label("ユーザ辞書", systemImage: "book.closed")
            }

            Section {
                HStack {
                    TextField("変換プロフィール", text: Binding(
                        get: { cachedZenzaiProfile ?? "" },
                        set: { newValue in
                            cachedZenzaiProfile = newValue
                            // UserDefaultsに直接保存（@ConfigStateを経由しない）
                            UserDefaults.standard.set(newValue, forKey: Config.ZenzaiProfile.key)
                        }
                    ), prompt: Text("例：田中太郎/高校生"))
                    helpButton(
                        helpContent: """
                        Zenzaiはあなたのプロフィールを考慮した変換を行うことができます。
                        名前や仕事、趣味などを入力すると、それに合わせた変換が自動で推薦されます。
                        （実験的な機能のため、精度が不十分な場合があります）
                        """,
                        isPresented: $zenzaiProfileHelpPopover
                    )
                }
            } header: {
                Label("変換プロフィール", systemImage: "brain")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - カスタマイズタブ
    @ViewBuilder
    private var customizeTabView: some View {
        Form {
            Section {
                Picker("入力方式", selection: Binding(
                    get: { cachedInputStyle ?? .default },
                    set: { newValue in
                        cachedInputStyle = newValue
                        // UserDefaultsに非同期で保存（メインスレッドをブロックしない）
                        Task.detached(priority: .userInitiated) {
                            if let encoded = try? JSONEncoder().encode(newValue) {
                                UserDefaults.standard.set(encoded, forKey: Config.InputStyle.key)
                            }
                        }
                    }
                )) {
                    Text("デフォルト").tag(Config.InputStyle.Value.default)
                    Text("かな入力（JIS）").tag(Config.InputStyle.Value.defaultKanaJIS)
                    Text("かな入力（US）").tag(Config.InputStyle.Value.defaultKanaUS)
                    Text("AZIK").tag(Config.InputStyle.Value.defaultAZIK)
                    Text("カスタム").tag(Config.InputStyle.Value.custom)
                }
                if cachedInputStyle == .custom {
                    Button("カスタム入力テーブルを編集") {
                        showingRomajiTableEditor = true
                    }
                }
            } header: {
                Label("入力方式", systemImage: "keyboard")
            }

            Section {
                Toggle("ライブ変換を有効化", isOn: Binding(
                    get: { cachedLiveConversion ?? false },
                    set: { newValue in
                        cachedLiveConversion = newValue
                        // UserDefaultsに直接保存（@ConfigStateを経由しない）
                        UserDefaults.standard.set(newValue, forKey: Config.LiveConversion.key)
                    }
                ))
                Toggle("円記号の代わりにバックスラッシュを入力", isOn: Binding(
                    get: { cachedTypeBackSlash ?? false },
                    set: { newValue in
                        cachedTypeBackSlash = newValue
                        // UserDefaultsに直接保存（@ConfigStateを経由しない）
                        UserDefaults.standard.set(newValue, forKey: Config.TypeBackSlash.key)
                    }
                ))
                Toggle("スペースは常に半角を入力", isOn: Binding(
                    get: { cachedTypeHalfSpace ?? false },
                    set: { newValue in
                        cachedTypeHalfSpace = newValue
                        // UserDefaultsに直接保存（@ConfigStateを経由しない）
                        UserDefaults.standard.set(newValue, forKey: Config.TypeHalfSpace.key)
                    }
                ))
                Picker("句読点の種類", selection: Binding(
                    get: { cachedPunctuationStyle ?? .kutenAndToten },
                    set: { newValue in
                        cachedPunctuationStyle = newValue
                        // UserDefaultsに非同期で保存（メインスレッドをブロックしない）
                        Task.detached(priority: .userInitiated) {
                            if let encoded = try? JSONEncoder().encode(newValue) {
                                UserDefaults.standard.set(encoded, forKey: Config.PunctuationStyle.key)
                            }
                        }
                    }
                )) {
                    Text("、と。").tag(Config.PunctuationStyle.Value.`kutenAndToten`)
                    Text("、と．").tag(Config.PunctuationStyle.Value.periodAndToten)
                    Text("，と。").tag(Config.PunctuationStyle.Value.kutenAndComma)
                    Text("，と．").tag(Config.PunctuationStyle.Value.periodAndComma)
                }
            } header: {
                Label("入力オプション", systemImage: "character.cursor.ibeam")
            }

            Section {
                Picker("履歴学習", selection: Binding(
                    get: { cachedLearning ?? .inputAndOutput },
                    set: { newValue in
                        cachedLearning = newValue
                        // UserDefaultsに非同期で保存（メインスレッドをブロックしない）
                        Task.detached(priority: .userInitiated) {
                            if let encoded = try? JSONEncoder().encode(newValue) {
                                UserDefaults.standard.set(encoded, forKey: Config.Learning.key)
                            }
                        }
                    }
                )) {
                    Text("学習する").tag(Config.Learning.Value.inputAndOutput)
                    Text("学習を停止").tag(Config.Learning.Value.onlyOutput)
                    Text("学習を無視").tag(Config.Learning.Value.nothing)
                }
                LabeledContent {
                    HStack {
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
                        Spacer()
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
    }

    // MARK: - 詳細設定タブ
    @ViewBuilder
    private var advancedTabView: some View {
        Form {
            Section {
                HStack {
                    TextField(
                        "Zenzaiの推論上限",
                        text: Binding(
                            get: { String(cachedInferenceLimit ?? Config.ZenzaiInferenceLimit.default) },
                            set: {
                                if let value = Int($0), (1 ... 50).contains(value) {
                                    cachedInferenceLimit = value
                                    // UserDefaultsに直接保存（@ConfigStateを経由しない）
                                    UserDefaults.standard.set(value, forKey: Config.ZenzaiInferenceLimit.key)
                                }
                            }
                        )
                    )
                    Stepper("", value: Binding(
                        get: { cachedInferenceLimit ?? Config.ZenzaiInferenceLimit.default },
                        set: { newValue in
                            cachedInferenceLimit = newValue
                            // UserDefaultsに直接保存（@ConfigStateを経由しない）
                            UserDefaults.standard.set(newValue, forKey: Config.ZenzaiInferenceLimit.key)
                        }
                    ), in: 1 ... 50)
                    .labelsHidden()
                    helpButton(
                        helpContent: "推論上限を小さくすると、入力中のもたつきが改善されることがあります。",
                        isPresented: $zenzaiInferenceLimitHelpPopover
                    )
                }
                Picker("パーソナライズ", selection: Binding(
                    get: { cachedZenzaiPersonalizationLevel ?? .normal },
                    set: { newValue in
                        cachedZenzaiPersonalizationLevel = newValue
                        // UserDefaultsに非同期で保存（メインスレッドをブロックしない）
                        Task.detached(priority: .userInitiated) {
                            if let encoded = try? JSONEncoder().encode(newValue) {
                                UserDefaults.standard.set(encoded, forKey: Config.ZenzaiPersonalizationLevel.key)
                            }
                        }
                    }
                )) {
                    Text("オフ").tag(Config.ZenzaiPersonalizationLevel.Value.off)
                    Text("弱く").tag(Config.ZenzaiPersonalizationLevel.Value.soft)
                    Text("普通").tag(Config.ZenzaiPersonalizationLevel.Value.normal)
                    Text("強く").tag(Config.ZenzaiPersonalizationLevel.Value.hard)
                }
            } header: {
                Label("Zenzai詳細設定", systemImage: "cpu")
            }

            Section {
                Picker("キーボード配列", selection: Binding(
                    get: { cachedKeyboardLayout ?? .qwerty },
                    set: { newValue in
                        cachedKeyboardLayout = newValue
                        // UserDefaultsに非同期で保存（メインスレッドをブロックしない）
                        Task.detached(priority: .userInitiated) {
                            if let encoded = try? JSONEncoder().encode(newValue) {
                                UserDefaults.standard.set(encoded, forKey: Config.KeyboardLayout.key)
                            }
                        }
                    }
                )) {
                    Text("QWERTY").tag(Config.KeyboardLayout.Value.qwerty)
                    Text("Colemak").tag(Config.KeyboardLayout.Value.colemak)
                    Text("Dvorak").tag(Config.KeyboardLayout.Value.dvorak)
                }
            } header: {
                Label("キーボード配列", systemImage: "keyboard.badge.ellipsis")
            }

            Section {
                Toggle("デバッグウィンドウを有効化", isOn: Binding(
                    get: { cachedDebugWindow ?? false },
                    set: { newValue in
                        cachedDebugWindow = newValue
                        // UserDefaultsに直接保存（@ConfigStateを経由しない）
                        UserDefaults.standard.set(newValue, forKey: Config.DebugWindow.key)
                    }
                ))
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
    }
}

#Preview {
    ConfigWindow()
}
