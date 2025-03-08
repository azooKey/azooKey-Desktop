//
//  ConfigWindow.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/23.
//

import SwiftUI

struct ConfigWindow: View {
    @ConfigState private var liveConversion = Config.LiveConversion()
    @ConfigState private var englishConversion = Config.EnglishConversion()
    @ConfigState private var typeBackSlash = Config.TypeBackSlash()
    @ConfigState private var typeCommaAndPeriod = Config.TypeCommaAndPeriod()
    @ConfigState private var zenzai = Config.ZenzaiIntegration()
    @ConfigState private var zenzaiProfile = Config.ZenzaiProfile()
    @ConfigState private var zenzaiPersonalizationLevel = Config.ZenzaiPersonalizationLevel()
    @ConfigState private var enableOpenAiApiKey = Config.EnableOpenAiApiKey()
    @ConfigState private var openAiApiKey = Config.OpenAiApiKey()
    @ConfigState private var learning = Config.Learning()
    @ConfigState private var inferenceLimit = Config.ZenzaiInferenceLimit()
    @ConfigState private var debugWindow = Config.DebugWindow()
    @ConfigState private var userDictionary = Config.UserDictionary()
    @ConfigState private var useCustomZenzModel = Config.UseCustomZenzModel()

    @State private var zenzaiHelpPopover = false
    @State private var zenzaiProfileHelpPopover = false
    @State private var zenzaiInferenceLimitHelpPopover = false
    @State private var openAiApiKeyPopover = false

    @State private var fileImporterPresented = false
    @State private var debugInfo: String = ""

    private var supportDirectory: URL {
        if #available(macOS 13, *) {
            URL.applicationSupportDirectory
                .appending(path: "azooKey", directoryHint: .isDirectory)
        } else {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("azooKey", isDirectory: true)
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
        VStack {
            Text("azooKey on macOS")
                .bold()
                .font(.title)
            Spacer()
            HStack {
                Spacer()
                ScrollView {
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
                        Toggle("英単語変換を有効化", isOn: $englishConversion)
                        Toggle("円記号の代わりにバックスラッシュを入力", isOn: $typeBackSlash)
                        Toggle("「、」「。」の代わりに「，」「．」を入力", isOn: $typeCommaAndPeriod)
                        Divider()
                        Button("ユーザ辞書を編集する") {
                            (NSApplication.shared.delegate as? AppDelegate)!.openUserDictionaryEditorWindow()
                        }
                        Divider()
                        Toggle("OpenAI APIキーの利用", isOn: $enableOpenAiApiKey)
                        HStack {
                            SecureField("OpenAI API", text: $openAiApiKey, prompt: Text("例:sk-xxxxxxxxxxx"))
                            helpButton(
                                helpContent: "OpenAI APIキーはローカルのみで管理され、外部に公開されることはありません。生成の際にAPIを利用するため、課金が発生します。",
                                isPresented: $openAiApiKeyPopover
                            )
                        }
                        Divider()
                        HStack {
                            Toggle("（開発者用）独自のGGUFの有効化", isOn: $useCustomZenzModel)
                                .labelsHidden()
                            Button("（開発者用）独自のGGUFを利用") {
                                self.fileImporterPresented = true
                            }.disabled(useCustomZenzModel.value == false)
                        }
                        Button("（開発者用）サポートディレクトリを開く") {
                            let folderURL = self.supportDirectory.deletingLastPathComponent()
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
                        }
                        Text(debugInfo)
                        Toggle("（開発者用）デバッグウィンドウを有効化", isOn: $debugWindow)
                    }
                    .fileImporter(isPresented: $fileImporterPresented, allowedContentTypes: [.init(filenameExtension: "gguf")!]) { item in
                        switch item {
                        case .success(let ggufURL):
                            guard ggufURL.startAccessingSecurityScopedResource() else {
                                return
                            }
                            do {
                                try FileManager.default.createDirectory(at: Config.UseCustomZenzModel.customZenzDirectoryURL(applicationSupportDirectory: self.supportDirectory), withIntermediateDirectories: true)
                                try FileManager.default.copyItem(
                                    at: ggufURL,
                                    to: Config.UseCustomZenzModel.customZenzFileURL(applicationSupportDirectory: self.supportDirectory)
                                )
                                self.useCustomZenzModel.value = true
                            } catch {
                                return
                            }
                        case .failure(let failure):
                            debugInfo = "Error: \(failure.localizedDescription)"
                        }

                    }
                }
                Spacer()
            }
            Spacer()
        }
        .frame(minHeight: 300, maxHeight: 600)
        .frame(minWidth: 400, maxWidth: 600)
    }
}

#Preview {
    ConfigWindow()
}
