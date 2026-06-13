#!/bin/sh
set -eu

service_name="dev.ensan.inputmethod.azooKeyMac.ConverterServer"
default_app_path="${BUILT_PRODUCTS_DIR:-/tmp/azooKeyDesktopDerivedData/Build/Products/Debug}/azooKeyMac.app"
app_path="${1:-${default_app_path}}"
server_path="${app_path}/Contents/MacOS/ConverterServer"
agent_dir="${HOME}/Library/LaunchAgents"
agent_path="${agent_dir}/${service_name}.plist"
gui_domain="gui/$(id -u)"
script_dir="$(cd "$(dirname "$0")" && pwd)"

if [ ! -x "${server_path}" ]; then
    echo "ConverterServer not found: ${server_path}" >&2
    echo "Build azooKeyMac first, or pass the app bundle path as the first argument." >&2
    exit 1
fi

"${script_dir}/write_converter_server_launch_agent.sh" "${agent_path}" "${server_path}" "${service_name}"

launchctl bootout "${gui_domain}" "${agent_path}" >/dev/null 2>&1 || true
launchctl bootstrap "${gui_domain}" "${agent_path}"
launchctl kickstart -k "${gui_domain}/${service_name}"
launchctl print "${gui_domain}/${service_name}" >/dev/null

echo "Installed and started ${service_name}"
echo "${agent_path}"
