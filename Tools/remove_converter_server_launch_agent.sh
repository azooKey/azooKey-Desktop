#!/bin/sh
set -eu

# XPC版からのアップグレード時に、KeepAlive付きの旧変換プロセスを停止する。
service_name="dev.ensan.inputmethod.azooKeyMac.ConverterServer"
system_agent_path="/Library/LaunchAgents/${service_name}.plist"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script with sudo to remove the legacy LaunchAgent." >&2
    exit 1
fi

# ログイン中の各ユーザーのサービスと、旧手動インストールのplistも片付ける。
# ホームディレクトリが /Users 以外にあるアカウントも扱う。
dscl . -list /Users UniqueID | while read -r account uid; do
    case "${uid}" in
        ''|*[!0-9]*) continue ;;
    esac
    if [ "${uid}" -lt 500 ]; then
        continue
    fi
    launchctl bootout "gui/${uid}/${service_name}" >/dev/null 2>&1 || true
    user_home="$(dscl . -read "/Users/${account}" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory: //')"
    if [ -n "${user_home}" ] && [ "${user_home}" != "/var/empty" ]; then
        rm -f "${user_home}/Library/LaunchAgents/${service_name}.plist"
    fi
done

rm -f "${system_agent_path}"
