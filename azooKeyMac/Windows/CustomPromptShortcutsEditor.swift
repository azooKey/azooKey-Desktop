//
//  CustomPromptShortcutsEditor.swift
//  azooKeyMac
//
//  Created by Claude Code
//

import SwiftUI

struct CustomPromptShortcutsEditor: View {
    @Binding var shortcuts: [CustomPromptShortcut]
    @State private var editingShortcut: CustomPromptShortcut?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shortcuts.isEmpty {
                HStack {
                    Text("ショートカットが設定されていません")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        Label("追加", systemImage: "plus")
                    }
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        Label("追加", systemImage: "plus")
                    }
                }

                List {
                    ForEach(shortcuts) { shortcut in
                        CustomPromptShortcutRow(
                            shortcut: shortcut,
                            onEdit: {
                                editingShortcut = shortcut
                            },
                            onDelete: {
                                shortcuts.removeAll { $0.id == shortcut.id }
                            }
                        )
                    }
                }
                .frame(minHeight: 150, maxHeight: 300)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CustomPromptShortcutEditSheet(
                shortcut: CustomPromptShortcut(
                    name: "",
                    prompt: "",
                    shortcut: KeyboardShortcut(key: "a", modifiers: .control)
                ),
                onSave: { newShortcut in
                    shortcuts.append(newShortcut)
                    showingAddSheet = false
                },
                onCancel: {
                    showingAddSheet = false
                }
            )
        }
        .sheet(item: $editingShortcut) { shortcut in
            CustomPromptShortcutEditSheet(
                shortcut: shortcut,
                onSave: { updatedShortcut in
                    if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                        shortcuts[index] = updatedShortcut
                    }
                    editingShortcut = nil
                },
                onCancel: {
                    editingShortcut = nil
                }
            )
        }
    }
}

struct CustomPromptShortcutRow: View {
    let shortcut: CustomPromptShortcut
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(shortcut.name)
                    .font(.system(size: 13, weight: .medium))
                Text(shortcut.prompt)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(shortcut.shortcut.displayString)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("編集")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .help("削除")
        }
        .padding(.vertical, 4)
    }
}

struct CustomPromptShortcutEditSheet: View {
    @State private var shortcut: CustomPromptShortcut
    let onSave: (CustomPromptShortcut) -> Void
    let onCancel: () -> Void

    init(shortcut: CustomPromptShortcut, onSave: @escaping (CustomPromptShortcut) -> Void, onCancel: @escaping () -> Void) {
        self._shortcut = State(initialValue: shortcut)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("カスタムプロンプトショートカットを編集")
                .font(.headline)

            Form {
                TextField("名前", text: $shortcut.name)
                    .help("例: 日本語に翻訳")

                TextField("プロンプト", text: $shortcut.prompt)
                    .help("例: japanese")

                LabeledContent("ショートカット") {
                    KeyboardShortcutRecorder(shortcut: $shortcut.shortcut)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("キャンセル") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    onSave(shortcut)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(shortcut.name.isEmpty || shortcut.prompt.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

#Preview {
    CustomPromptShortcutsEditor(
        shortcuts: .constant([
            CustomPromptShortcut(
                name: "日本語に翻訳",
                prompt: "japanese",
                shortcut: KeyboardShortcut(key: "j", modifiers: .control)
            ),
            CustomPromptShortcut(
                name: "英語に翻訳",
                prompt: "english",
                shortcut: KeyboardShortcut(key: "e", modifiers: .control)
            )
        ])
    )
}
