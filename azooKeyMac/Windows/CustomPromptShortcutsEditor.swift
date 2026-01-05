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
                Text("ショートカットが設定されていません")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
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
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 200)
            }

            HStack {
                Spacer()
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("追加", systemImage: "plus")
                }
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(shortcut.name)
                    .font(.system(size: 12))
                Text(shortcut.prompt)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(shortcut.shortcut.displayString)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("編集")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.red.opacity(0.8))
            .help("削除")
        }
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
