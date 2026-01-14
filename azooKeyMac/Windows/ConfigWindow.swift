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
    @ConfigState private var debugPredictiveTyping = Config.DebugPredictiveTyping()
    @ConfigState private var userDictionary = Config.UserDictionary()
    @ConfigState private var systemUserDictionary = Config.SystemUserDictionary()
    @ConfigState private var keyboardLayout = Config.KeyboardLayout()
    @ConfigState private var aiBackend = Config.AIBackendPreference()

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
    @State private var availabilityCheckDone = false

    private enum Tab: String, CaseIterable, Hashable {
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
            // カスタムタブバー
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
        .sheet(isPresented: $showingRomajiTableEditor) {
            RomajiTableEditorWindow(base: CustomInputTableStore.loadTable()) { exported in
                do {
                    _ = try CustomInputTableStore.save(exported: exported)
                    CustomInputTableStore.registerIfExists()
                } catch {
                    print("Failed to save custom input table: \(error)")
                }
            }
        }
    }

    // MARK: - 基本タブ
    @ViewBuilder
    private var basicTabView: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
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
                }

                if aiBackend.value == .openAI {
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
            } header: {
                Label("いい感じ変換", systemImage: "sparkles")
            }

            Section {
                LabeledContent {
                    HStack {
                        Text("\(self.userDictionary.value.items.count)件のアイテム")
                        Button("編集") {
                            (NSApplication.shared.delegate as? AppDelegate)!.openUserDictionaryEditorWindow()
                        }
                    }
                } label: {
                    Text("azooKeyユーザ辞書")
                }
                LabeledContent {
                    HStack {
                        switch self.systemUserDictionaryUpdateMessage {
                        case .none:
                            if let updated = self.systemUserDictionary.value.lastUpdate {
                                let date = updated.formatted(date: .omitted, time: .omitted)
                                Text("最終更新: \(date) / \(self.systemUserDictionary.value.items.count)件のアイテム")
                            } else {
                                Text("未設定")
                            }
                        case .error(let error):
                            Text("読み込みエラー: \(error.localizedDescription)")
                        case .successfulUpdate:
                            Text("読み込みに成功しました / \(self.systemUserDictionary.value.items.count)件のアイテム")
                        }
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
                } label: {
                    Text("システムのユーザ辞書")
                }
            } header: {
                Label("ユーザ辞書", systemImage: "book.closed")
            }

            Section {
                Toggle("ライブ変換を有効化", isOn: $liveConversion)
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
            } header: {
                Label("変換設定", systemImage: "brain")
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

            Section {
                Picker("履歴学習", selection: $learning) {
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

            Section {
                Picker("入力方式", selection: $inputStyle) {
                    Text("デフォルト").tag(Config.InputStyle.Value.default)
                    Text("かな入力（JIS）").tag(Config.InputStyle.Value.defaultKanaJIS)
                    Text("かな入力（US）").tag(Config.InputStyle.Value.defaultKanaUS)
                    Text("AZIK").tag(Config.InputStyle.Value.defaultAZIK)
                    Text("カスタム").tag(Config.InputStyle.Value.custom)
                }
                if inputStyle.value == .custom {
                    LabeledContent {
                        Button("編集") {
                            showingRomajiTableEditor = true
                        }
                    } label: {
                        Text("カスタム入力テーブル")
                    }
                }
            } header: {
                Label("入力方式", systemImage: "keyboard")
            }

            Section {
                Picker("キーボード配列", selection: $keyboardLayout) {
                    Text("QWERTY").tag(Config.KeyboardLayout.Value.qwerty)
                    Text("Australian").tag(Config.KeyboardLayout.Value.australian)
                    Text("Colemak").tag(Config.KeyboardLayout.Value.colemak)
                    Text("Dvorak").tag(Config.KeyboardLayout.Value.dvorak)
                    Text("Dvorak - QWERTY ⌘").tag(Config.KeyboardLayout.Value.dvorakQwertyCommand)
                }
            } header: {
                Label("キーボード配列", systemImage: "keyboard.badge.ellipsis")
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
                            get: {
                                String(self.$inferenceLimit.wrappedValue)
                            },
                            set: {
                                if let value = Int($0), (1 ... 50).contains(value) {
                                    self.$inferenceLimit.wrappedValue = value
                                }
                            }
                        )
                    )
                    Stepper("", value: $inferenceLimit, in: 1 ... 50)
                        .labelsHidden()
                    helpButton(helpContent: "推論上限を小さくすると、入力中のもたつきが改善されることがあります。", isPresented: $zenzaiInferenceLimitHelpPopover)
                }
            } header: {
                Label("Zenzai設定", systemImage: "cpu")
            }

            Section {
                Toggle("デバッグウィンドウを有効化", isOn: $debugWindow)
                Toggle("開発中の予測入力を有効化", isOn: $debugPredictiveTyping)
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
                .textSelection(.enabled)
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
