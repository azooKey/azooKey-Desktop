#!/bin/sh
set -eu

agent_path="$1"
server_path="$2"
service_name="${3:-dev.ensan.inputmethod.azooKeyMac.ConverterServer}"

agent_dir="$(dirname "${agent_path}")"
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
