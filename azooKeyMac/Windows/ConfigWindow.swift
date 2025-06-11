import Core
import SwiftUI

struct ConfigWindow: View {
    @ConfigState private var liveConversion = Config.LiveConversion()
    @ConfigState private var typeBackSlash = Config.TypeBackSlash()
    @ConfigState private var typeCommaAndPeriod = Config.TypeCommaAndPeriod()
    @ConfigState private var typeHalfSpace = Config.TypeHalfSpace()
    @ConfigState private var zenzai = Config.ZenzaiIntegration()
    @ConfigState private var zenzaiProfile = Config.ZenzaiProfile()
    @ConfigState private var zenzaiPersonalizationLevel = Config.ZenzaiPersonalizationLevel()
    @ConfigState private var enableOpenAiApiKey = Config.EnableOpenAiApiKey()
    @ConfigState private var openAiApiKey = Config.OpenAiApiKey()
    @ConfigState private var openAiModelName = Config.OpenAiModelName()
    @ConfigState private var llmProvider = Config.LLMProvider()
    @ConfigState private var enableGeminiApiKey = Config.EnableGeminiApiKey()
    @ConfigState private var geminiApiKey = Config.GeminiApiKey()
    @ConfigState private var geminiModelName = Config.GeminiModelName()
    @ConfigState private var customLLMEndpoint = Config.CustomLLMEndpoint()
    @ConfigState private var enableExternalLLM = Config.EnableExternalLLM()
    @ConfigState private var learning = Config.Learning()
    @ConfigState private var inferenceLimit = Config.ZenzaiInferenceLimit()
    @ConfigState private var debugWindow = Config.DebugWindow()
    @ConfigState private var userDictionary = Config.UserDictionary()

    @State private var zenzaiHelpPopover = false
    @State private var zenzaiProfileHelpPopover = false
    @State private var zenzaiInferenceLimitHelpPopover = false
    @State private var openAiApiKeyPopover = false
    @State private var geminiApiKeyPopover = false
    @State private var llmProviderHelpPopover = false
    @State private var externalLLMHelpPopover = false
    @State private var connectionTestResult: String = ""
    @State private var isTestingConnection = false
    @State private var showTestResult = false

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

    private func canTestConnection() -> Bool {
        guard enableExternalLLM.value else {
            return false
        }

        switch llmProvider.value {
        case "openai":
            return enableOpenAiApiKey.value && !openAiApiKey.value.isEmpty && !openAiModelName.value.isEmpty
        case "gemini":
            return enableGeminiApiKey.value && !geminiApiKey.value.isEmpty && !geminiModelName.value.isEmpty
        case "custom":
            return !customLLMEndpoint.value.isEmpty && !openAiApiKey.value.isEmpty && !openAiModelName.value.isEmpty
        default:
            return false
        }
    }

    func testConnection() {
        isTestingConnection = true
        showTestResult = false

        Task {
            let providerType = LLMProviderType(from: llmProvider.value)
            var apiKey = ""
            var modelName = ""
            var endpoint: String?

            switch providerType {
            case .openai:
                apiKey = openAiApiKey.value
                modelName = openAiModelName.value
            case .gemini:
                apiKey = geminiApiKey.value
                modelName = geminiModelName.value
            case .custom:
                endpoint = customLLMEndpoint.value
                apiKey = openAiApiKey.value
                modelName = openAiModelName.value
            }

            let result = await LLMConnectionTester.testConnection(
                provider: providerType,
                apiKey: apiKey,
                modelName: modelName,
                endpoint: endpoint
            )

            await MainActor.run {
                switch result {
                case .success(let message):
                    connectionTestResult = "✅ \(message)"
                case .failure(let error):
                    connectionTestResult = "❌ \(error)"
                }
                isTestingConnection = false
                showTestResult = true

                // Hide result after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    showTestResult = false
                }
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
                    Toggle("ライブ変換を有効化", isOn: $liveConversion)
                    Toggle("円記号の代わりにバックスラッシュを入力", isOn: $typeBackSlash)
                    Toggle("「、」「。」の代わりに「，」「．」を入力", isOn: $typeCommaAndPeriod)
                    Toggle("スペースは常に半角を入力", isOn: $typeHalfSpace)
                    Divider()
                    Button("ユーザ辞書を編集する") {
                        (NSApplication.shared.delegate as? AppDelegate)!.openUserDictionaryEditorWindow()
                    }
                    Divider()
                    Toggle("（開発者用）デバッグウィンドウを有効化", isOn: $debugWindow)

                    // External LLM Usage Toggle
                    HStack {
                        Toggle("外部LLMを使用", isOn: $enableExternalLLM)
                        helpButton(
                            helpContent: "いい感じ変換機能で外部LLM（OpenAI、Gemini、カスタムエンドポイント）を使用するかどうかを設定します。無効にするとローカルのZenzaiエンジンのみが使用されます。",
                            isPresented: $externalLLMHelpPopover
                        )
                    }

                    // LLM Provider Selection (only shown when external LLM is enabled)
                    if enableExternalLLM.value {
                        HStack {
                            Picker("LLMプロバイダー", selection: $llmProvider) {
                                Text("OpenAI").tag("openai")
                                Text("Google Gemini").tag("gemini")
                                Text("カスタム").tag("custom")
                            }
                            helpButton(
                                helpContent: "いい感じ変換機能で使用するLLMプロバイダーを選択してください。\n• OpenAI: ChatGPT API\n• Google Gemini: Gemini API\n• カスタム: 独自のエンドポイント",
                                isPresented: $llmProviderHelpPopover
                            )
                        }
                    }

                    // LLM Settings (only shown when external LLM is enabled)
                    if enableExternalLLM.value {
                        // OpenAI Settings
                        if llmProvider.value == "openai" {
                            Toggle("OpenAI APIキーの利用", isOn: $enableOpenAiApiKey)
                            HStack {
                                SecureField("OpenAI API", text: $openAiApiKey, prompt: Text("例:sk-xxxxxxxxxxx"))
                                    .disabled(!enableOpenAiApiKey.value)
                                helpButton(
                                    helpContent: "OpenAI APIキーはローカルのみで管理され、外部に公開されることはありません。生成の際にAPIを利用するため、課金が発生します。",
                                    isPresented: $openAiApiKeyPopover
                                )
                            }
                            TextField("OpenAI Model Name", text: $openAiModelName, prompt: Text("例: gpt-4o-mini"))
                                .disabled(!enableOpenAiApiKey.value)
                        }

                        // Gemini Settings
                        if llmProvider.value == "gemini" {
                            Toggle("Gemini APIキーの利用", isOn: $enableGeminiApiKey)
                            HStack {
                                SecureField("Gemini API", text: $geminiApiKey, prompt: Text("例:AIza..."))
                                    .disabled(!enableGeminiApiKey.value)
                                helpButton(
                                    helpContent: "Gemini APIキーはローカルのみで管理され、外部に公開されることはありません。Google AI Studioから取得できます。",
                                    isPresented: $geminiApiKeyPopover
                                )
                            }
                            TextField("Gemini Model Name", text: $geminiModelName, prompt: Text("例: gemini-1.5-flash"))
                                .disabled(!enableGeminiApiKey.value)
                        }

                        // Custom Endpoint Settings (OpenAI API compatible)
                        if llmProvider.value == "custom" {
                            TextField("カスタムエンドポイントURL", text: $customLLMEndpoint, prompt: Text("例: https://api.example.com/v1/chat/completions"))

                            Text("API設定（OpenAI形式またはGemini互換エンドポイント用）")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextField("APIキー", text: $openAiApiKey, prompt: Text("例: sk-xxx... または AIza..."))
                            TextField("モデル名", text: $openAiModelName, prompt: Text("例: gpt-4o-mini または gemini-1.5-flash"))

                            Text("Gemini互換の場合: https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Connection Test Button
                        HStack {
                            Button(action: testConnection) {
                                HStack {
                                    if isTestingConnection {
                                        ProgressView()
                                            .scaleEffect(0.5)
                                    }
                                    Text(isTestingConnection ? "テスト中..." : "接続テスト")
                                }
                            }
                            .disabled(isTestingConnection || !canTestConnection())

                            if showTestResult && !connectionTestResult.isEmpty {
                                Text(connectionTestResult)
                                    .foregroundColor(connectionTestResult.contains("成功") ? .green : .red)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
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
