import Foundation

/// 日本語モードで変換中の文字がないときに押した「/」を、変換を待たずに半角で入力する
///
/// Claude Codeのように行頭の「/」でコマンドを入力するアプリで、日本語モードのまま「/」を打てるようにする。
/// 変換中の文字があるときの「/」は、`UserAction.SymbolWidthOptions.typeHalfWidthSlash` で半角にする。
public enum SlashDirectInputResolver {
    public static func resolve(
        characters: String?,
        modifierFlags: KeyEventCore.ModifierFlag,
        inputLanguage: InputLanguage,
        inputState: InputState,
        inputStyle: Config.InputStyle.Value
    ) -> String? {
        guard inputLanguage == .japanese,
              inputState == .none,
              modifierFlags.isEmpty,
              characters == "/" else {
            return nil
        }
        return switch inputStyle {
        case .default, .defaultAZIK, .custom:
            "/"
        case .defaultKanaJIS, .defaultKanaUS:
            // かな入力では「/」のキーで「め」を入力する
            nil
        }
    }
}
