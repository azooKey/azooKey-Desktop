import Core
import SwiftUI

struct ConfigWindow: View {
    @ConfigState private var liveConversion = Config.LiveConversion()
    @ConfigState private var inputStyle = Config.InputStyle()
    @ConfigState private var typeBackSlash = Config.TypeBackSlash()
    @ConfigState private var typeCommaAndPeriod = Config.TypeCommaAndPeriod()
    @ConfigState private var typeHalfSpace = Config.TypeHalfSpace()
    @ConfigState private var zenzai = Config.ZenzaiIntegration()
    @ConfigState private var zenzaiProfile = Config.ZenzaiProfile()
    @ConfigState private var zenzaiPersonalizationLevel = Config.ZenzaiPersonalizationLevel()
    @ConfigState private var enableOpenAiApiKey = Config.EnableOpenAiApiKey()
    @ConfigState private var openAiApiKey = Config.OpenAiApiKey()
    @ConfigState private var openAiModelName = Config.OpenAiModelName()
    @ConfigState private var openAiApiEndpoint = Config.OpenAiApiEndpoint()
    @ConfigState private var learning = Config.Learning()
    @ConfigState private var inferenceLimit = Config.ZenzaiInferenceLimit()
    @ConfigState private var debugWindow = Config.DebugWindow()
    @ConfigState private var userDictionary = Config.UserDictionary()
    @ConfigState private var systemUserDictionary = Config.SystemUserDictionary()

    @State private var zenzaiHelpPopover = false
    @State private var zenzaiProfileHelpPopover = false
    @State private var zenzaiInferenceLimitHelpPopover = false
    @State private var openAiApiKeyPopover = false
    @State private var connectionTestInProgress = false
    @State private var connectionTestResult: String?
    @State private var systemUserDictionaryUpdateMessage: SystemUserDictionaryUpdateMessage?

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
        VStack {
            Text("azooKey on macOS")
                .bold()
                .font(.title)
            Spacer()
            HStack {
                Spacer()
                Form {

                    Picker("履歴学習", selection: $learning) {
                        Text("学習する").tag(Config.Learning.Value.inputAndOutput)
                        Text("学習を停止").tag(Config.Learning.Value.onlyOutput)
                        Text("学習を無視").tag(Config.Learning.Value.nothing)
                    }
                    Picker("パーソナライズ", selection: $zenzaiPersonalizationLevel) {
                        Text("オフ").tag(Config.ZenzaiPersonalizationLevel.Value.off)
                        Text("弱く").tag(Config.ZenzaiPersonalizationLevel.Value.soft)
                        Text("普通").tag(Config.ZenzaiPersonalizationLevel.Value.normal)
                        Text("強く").tag(Config.ZenzaiPersonalizationLevel.Value.hard)
                    }
                    Divider()
                    HStack {
                        Toggle("Zenzaiを有効化", isOn: $zenzai)
                        helpButton(helpContent: "Zenzaiはニューラル言語モデルを利用した最新のかな漢字変換システムです。\nMacのGPUを利用して高精度な変換を行います。\n変換エンジンはローカルで動作するため、外部との通信は不要です。", isPresented: $zenzaiHelpPopover)
                    }
                    HStack {
                        TextField("変換プロフィール", text: $zenzaiProfile, prompt: Text("例：田中太郎/高校生"))
                            .disabled(!zenzai.value)
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
                        .disabled(!zenzai.value)
                        Stepper("", value: $inferenceLimit, in: 1 ... 50)
                            .labelsHidden()
                            .disabled(!zenzai.value)
                        helpButton(helpContent: "推論上限を小さくすると、入力中のもたつきが改善されることがあります。", isPresented: $zenzaiInferenceLimitHelpPopover)
                    }
                    Divider()
                    Picker("入力方式", selection: $inputStyle) {
                        Text("デフォルト").tag(Config.InputStyle.Value.default)
                        Text("かな入力（JIS）").tag(Config.InputStyle.Value.defaultKanaJIS)
                        Text("かな入力（US）").tag(Config.InputStyle.Value.defaultKanaUS)
                        Text("AZIK（β版）").tag(Config.InputStyle.Value.defaultAZIK)
                    }
                    Divider()
                    Toggle("ライブ変換を有効化", isOn: $liveConversion)
                    Toggle("円記号の代わりにバックスラッシュを入力", isOn: $typeBackSlash)
                    Toggle("「、」「。」の代わりに「，」「．」を入力", isOn: $typeCommaAndPeriod)
                    Toggle("スペースは常に半角を入力", isOn: $typeHalfSpace)
                    Divider()
                    LabeledContent {
                        HStack {
                            Button("編集") {
                                (NSApplication.shared.delegate as? AppDelegate)!.openUserDictionaryEditorWindow()
                            }
                            Spacer()
                            Text("\(self.userDictionary.value.items.count)件のアイテム")
                        }
                    } label: {
                        Text("azooKeyユーザ辞書")
                    }
                    LabeledContent {
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
                        Spacer()
                        switch self.systemUserDictionaryUpdateMessage {
                        case .none:
                            if let updated = self.systemUserDictionary.value.lastUpdate {
                                let date = updated.formatted(date: .omitted, time: .omitted)
                                Text("最終更新: \(updated) / \(self.systemUserDictionary.value.items.count)件のアイテム")
                            } else {
                                Text("未設定")
                            }
                        case .error(let error):
                            Text("読み込みエラー: \(error.localizedDescription)")
                        case .successfulUpdate:
                            Text("読み込みに成功しました / \(self.systemUserDictionary.value.items.count)件のアイテム")
                        }

                    } label: {
                        Text("システムのユーザ辞書")
                    }
                    Divider()
                    Toggle("（開発者用）デバッグウィンドウを有効化", isOn: $debugWindow)
                    Toggle("OpenAI APIキーの利用", isOn: $enableOpenAiApiKey)
                    HStack {
                        SecureField("OpenAI API", text: $openAiApiKey, prompt: Text("例:sk-xxxxxxxxxxx"))
                        helpButton(
                            helpContent: "OpenAI APIキーはローカルのみで管理され、外部に公開されることはありません。生成の際にAPIを利用するため、課金が発生します。",
                            isPresented: $openAiApiKeyPopover
                        )
                    }
                    TextField("OpenAI Model Name", text: $openAiModelName, prompt: Text("例: gpt-4o-mini"))
                        .disabled(!$enableOpenAiApiKey.wrappedValue)
                    TextField("API Endpoint", text: $openAiApiEndpoint, prompt: Text("例: https://api.openai.com/v1/chat/completions"))
                        .disabled(!$enableOpenAiApiKey.wrappedValue)
                        .help("例: https://api.openai.com/v1/chat/completions\nGemini: https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")

                    HStack {
                        Button("接続テスト") {
                            Task {
                                await testConnection()
                            }
                        }
                        .disabled(!$enableOpenAiApiKey.wrappedValue || connectionTestInProgress || openAiApiKey.value.isEmpty)

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
                    LabeledContent("Version") {
                        Text(PackageMetadata.gitTag ?? PackageMetadata.gitCommit ?? "Unknown Version")
                            .monospaced()
                            .bold()
                            .copyable([
                                PackageMetadata.gitTag ?? PackageMetadata.gitCommit ?? "Unknown Version"
                            ])
                    }
                    .textSelection(.enabled)
                }
                .frame(width: 450)
                Spacer()
            }
            Spacer()
        }
        .fixedSize()
        .frame(width: 500)
    }
}

#Preview {
    ConfigWindow()
}
