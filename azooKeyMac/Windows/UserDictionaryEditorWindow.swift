//
//  UserDictionaryEditorWindow.swift
//  azooKeyMac
//
//  Created by miwa on 2024/09/22.
//

import Core
import SwiftUI

struct UserDictionaryEditorWindow: View {

    @ConfigState private var userDictionary = Config.UserDictionary()

    @State private var editTargetID: UUID?
    @State private var undoItem: Config.UserDictionaryEntry?

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

    private var isAdditionDisabled: Bool {
        self.userDictionary.value.items.count >= 50
    }

    var body: some View {
        VStack {
            Text("ユーザ辞書の設定")
                .bold()
                .font(.title)
            Text("この機能はβ版です。予告なく仕様を変更することがあるほか、最大50件に限定しています。")
                .font(.caption)
            Spacer()
            if let editTargetID {
                let itemBinding = Binding(
                    get: {
                        self.userDictionary.value.items.first {
                            $0.id == editTargetID
                        } ?? .init(word: "", reading: "")
                    },
                    set: {
                        if let index = self.userDictionary.value.items.firstIndex(where: {
                            $0.id == editTargetID
                        }) {
                            self.userDictionary.value.items[index] = $0
                        }
                    }
                )
                Form {
                    TextField("単語", text: itemBinding.word)
                    TextField("読み", text: itemBinding.reading)
                    TextField("ヒント", text: itemBinding.nonNullHint)
                    HStack {
                        Spacer()
                        Button("完了", systemImage: "checkmark") {
                            self.editTargetID = nil
                        }
                        Spacer()
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("追加", systemImage: "plus") {
                        let newItem = Config.UserDictionaryEntry(word: "", reading: "", hint: nil)
                        self.userDictionary.value.items.append(newItem)
                        self.editTargetID = newItem.id
                        self.undoItem = nil
                    }
                    .disabled(self.isAdditionDisabled)
                    if self.isAdditionDisabled {
                        Label("50件を超えています", systemImage: "exclamationmark.octagon")
                            .foregroundStyle(.red)
                    }
                    if let undoItem {
                        Button("元に戻す", systemImage: "arrow.uturn.backward") {
                            self.userDictionary.value.items.append(undoItem)
                            self.undoItem = nil
                        }
                    }
                    Spacer()
                }
            }
            HStack {
                Spacer()
                Table(self.userDictionary.value.items) {
                    TableColumn("") { item in
                        HStack {
                            Button("編集する", systemImage: "pencil") {
                                self.editTargetID = item.id
                                self.undoItem = nil
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            Button("削除する", systemImage: "trash", role: .destructive) {
                                if let itemIndex = self.userDictionary.value.items.firstIndex(where: {
                                    $0.id == item.id
                                }) {
                                    self.undoItem = self.userDictionary.value.items[itemIndex]
                                    self.userDictionary.value.items.remove(at: itemIndex)
                                }
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                        }
                    }
                    TableColumn("単語", value: \.word)
                    TableColumn("読み", value: \.reading)
                    TableColumn("ヒント", value: \.nonNullHint)
                }
                .disabled(editTargetID != nil)
                Spacer()
            }
            Spacer()
        }
        .frame(minHeight: 300, maxHeight: 600)
        .frame(minWidth: 600, maxWidth: 800)
    }
}

#Preview {
    UserDictionaryEditorWindow()
}
