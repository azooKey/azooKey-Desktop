#!/bin/sh
set -eu

service_name="dev.ensan.inputmethod.azooKeyMac.ConverterServer"
default_app_path="${BUILT_PRODUCTS_DIR:-/tmp/azooKeyDesktopDerivedData/Build/Products/Debug}/azooKeyMac.app"
app_path="${1:-${default_app_path}}"
server_path="${app_path}/Contents/MacOS/ConverterServer"
agent_dir="${HOME}/Library/LaunchAgents"
agent_path="${agent_dir}/${service_name}.plist"
gui_domain="gui/$(id -u)"

if [ ! -x "${server_path}" ]; then
    echo "ConverterServer not found: ${server_path}" >&2
    echo "Build azooKeyMac first, or pass the app bundle path as the first argument." >&2
    exit 1
fi

mkdir -p "${agent_dir}"
cat > "${agent_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${service_name}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${server_path}</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>${service_name}</key>
        <true/>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/${service_name}.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/${service_name}.stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootout "${gui_domain}" "${agent_path}" >/dev/null 2>&1 || true
launchctl bootstrap "${gui_domain}" "${agent_path}"
launchctl kickstart -k "${gui_domain}/${service_name}"
launchctl print "${gui_domain}/${service_name}" >/dev/null

echo "Installed and started ${service_name}"
echo "${agent_path}"
