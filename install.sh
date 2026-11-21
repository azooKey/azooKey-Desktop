#!/bin/bash
set -xe -o pipefail

IGNORE_LINT=false
DRY_RUN=false
NO_PKILL=false
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command-line options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ignore-lint) IGNORE_LINT=true ;;
        --dry-run) DRY_RUN=true ;;
        --no-pkill) NO_PKILL=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ "$IGNORE_LINT" = false ]; then
    if command -v swiftlint &> /dev/null
    then
        # Fix auto-fixable errors
        swiftlint --fix --format
        # Check other errors
        swiftlint --quiet --strict
    else
        echo "swiftlint could not be found. Please rerun the script as \`./install.sh --ignore-lint\`."
        echo "For contributing azooKey on macOS, we strongly recommend you to install swiftlint"
        echo "To install swiftlint, run \`brew install swiftlint\`"
        exit 1
    fi
else
    echo "Skipping swiftlint checks due to --ignore-lint option."
fi


# Check if xcpretty is installed
if command -v xcpretty &> /dev/null
then
    xcodebuild -project azooKeyMac.xcodeproj -scheme azooKeyMac clean archive -archivePath build/archive.xcarchive -allowProvisioningUpdates | xcpretty
else
    echo "xcpretty could not be found. Proceeding without xcpretty."
    xcodebuild -project azooKeyMac.xcodeproj -scheme azooKeyMac clean archive -archivePath build/archive.xcarchive -allowProvisioningUpdates
fi

ARCHIVED_APP="build/archive.xcarchive/Products/Applications/azooKeyMac.app"
INSTALLED_APP="/Library/Input Methods/azooKeyMac.app"

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN: Would execute the following commands:"
    echo "  sudo ${REPO_ROOT}/Tools/remove_converter_server_launch_agent.sh"
    printf '  sudo rm -rf %q\n' "$INSTALLED_APP"
    printf '  sudo ditto %q %q\n' "$ARCHIVED_APP" "$INSTALLED_APP"
    if [ "$NO_PKILL" = false ]; then
        echo "  pkill azooKeyMac || true"
    fi
    echo "Build completed successfully. Use without --dry-run to actually install."
else
    sudo "${REPO_ROOT}/Tools/remove_converter_server_launch_agent.sh"
    sudo rm -rf "$INSTALLED_APP"
    # Preserve the symlinks in versioned frameworks so their signatures remain valid.
    sudo ditto "$ARCHIVED_APP" "$INSTALLED_APP"
    if [ "$NO_PKILL" = false ]; then
        pkill azooKeyMac || true
    fi
fi
