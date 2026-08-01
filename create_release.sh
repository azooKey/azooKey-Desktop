#!/bin/bash
set -euo pipefail

PROJECT_NAME="azooKeyMac"
SCHEME="azooKeyMac"
CONFIGURATION="Release"
PKG_PATH="./azooKey-release-signed.pkg"
APPCAST_PATH="./build/release/appcast.xml"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-azooKey/azooKey-Desktop}"
GIT_REMOTE="${GIT_REMOTE:-origin}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
TEST_RELEASE_TAG="${TEST_RELEASE_TAG:-sparkle-update-test}"

release_kind=""
tag_name=""

usage() {
  cat <<'EOF'
Usage:
  ./create_release.sh --stable-release
  ./create_release.sh --pre-release
  ./create_release.sh --test-release

Options:
  --stable-release     Create a stable GitHub Release and mark it as latest.
  --pre-release        Create a GitHub pre-release. It is not marked as latest.
  --test-release       Create or update the fixed test release for update verification.
  --tag TAG            Override the generated tag name.
  --repo OWNER/REPO    GitHub repository to upload to. Default: azooKey/azooKey-Desktop.
  --remote REMOTE      Git remote used for pushing the tag. Default: origin.
  -h, --help           Show this help.

Required environment:
  SPARKLE_PUBLIC_ED_KEY  Sparkle EdDSA public key embedded into the app.

Optional environment:
  SPARKLE_SIGN_UPDATE    Path to Sparkle's sign_update tool.
  SPARKLE_FEED_URL       Appcast URL embedded into the app.
  TEST_RELEASE_TAG       Fixed tag used by --test-release. Default: sparkle-update-test.
  GITHUB_REPOSITORY      Default value for --repo.
  GIT_REMOTE             Default value for --remote.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

read_build_setting() {
  local key="$1"
  awk -v key="$key" '
    $1 == key {
      value = $3
      sub(/;$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "${PROJECT_NAME}.xcodeproj/project.pbxproj"
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

find_sign_update() {
  if [ -n "${SPARKLE_SIGN_UPDATE:-}" ]; then
    [ -x "${SPARKLE_SIGN_UPDATE}" ] || fail "SPARKLE_SIGN_UPDATE is not executable: ${SPARKLE_SIGN_UPDATE}"
    printf '%s\n' "${SPARKLE_SIGN_UPDATE}"
    return
  fi

  local candidate
  for candidate in \
    "./build/source-packages/artifacts/sparkle/Sparkle/bin/sign_update" \
    "./.build/artifacts/sparkle/Sparkle/bin/sign_update" \
    "${HOME}/Library/Developer/Xcode/DerivedData"/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
  do
    if [ -x "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done

  fail "Sparkle sign_update was not found. Set SPARKLE_SIGN_UPDATE to its path."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stable-release)
      [ -z "${release_kind}" ] || fail "choose only one of --stable-release, --pre-release, or --test-release"
      release_kind="stable"
      ;;
    --pre-release)
      [ -z "${release_kind}" ] || fail "choose only one of --stable-release, --pre-release, or --test-release"
      release_kind="pre"
      ;;
    --test-release)
      [ -z "${release_kind}" ] || fail "choose only one of --stable-release, --pre-release, or --test-release"
      release_kind="test"
      ;;
    --tag)
      shift
      [ "$#" -gt 0 ] || fail "--tag requires a value"
      tag_name="$1"
      ;;
    --repo)
      shift
      [ "$#" -gt 0 ] || fail "--repo requires a value"
      GITHUB_REPOSITORY="$1"
      ;;
    --remote)
      shift
      [ "$#" -gt 0 ] || fail "--remote requires a value"
      GIT_REMOTE="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

[ -n "${release_kind}" ] || fail "choose --stable-release, --pre-release, or --test-release"
[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ] || fail "SPARKLE_PUBLIC_ED_KEY is required"

require_command git
require_command gh
require_command awk
require_command date
require_command sed
require_command tr

if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "tracked files have uncommitted changes. Commit before creating a release."
fi

marketing_version="$(read_build_setting MARKETING_VERSION)"
build_version="$(read_build_setting CURRENT_PROJECT_VERSION)"
[ -n "${marketing_version}" ] || fail "MARKETING_VERSION was not found"
[ -n "${build_version}" ] || fail "CURRENT_PROJECT_VERSION was not found"

if [ -z "${tag_name}" ]; then
  if [ "${release_kind}" = "stable" ]; then
    tag_name="v${marketing_version}"
  elif [ "${release_kind}" = "pre" ]; then
    tag_name="v${marketing_version}-pre.${build_version}"
  else
    tag_name="${TEST_RELEASE_TAG}"
  fi
fi

if [ -z "${SPARKLE_FEED_URL}" ]; then
  if [ "${release_kind}" = "test" ]; then
    SPARKLE_FEED_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag_name}/appcast.xml"
  else
    SPARKLE_FEED_URL="https://github.com/${GITHUB_REPOSITORY}/releases/latest/download/appcast.xml"
  fi
fi

if [ "${release_kind}" = "test" ] && [[ "${tag_name}" =~ ^v[0-9] ]]; then
  fail "--test-release refuses to force-update a version-like tag: ${tag_name}"
fi

if [ "${release_kind}" != "test" ]; then
  if git rev-parse -q --verify "refs/tags/${tag_name}" >/dev/null; then
    fail "local tag already exists: ${tag_name}"
  fi
  if git ls-remote --exit-code --tags "${GIT_REMOTE}" "refs/tags/${tag_name}" >/dev/null 2>&1; then
    fail "remote tag already exists: ${tag_name}"
  fi
fi

rm -f "${PKG_PATH}"

DERIVED_DATA_PATH="./build/derived-data" \
CLONED_SOURCE_PACKAGES_DIR_PATH="./build/source-packages" \
SPARKLE_FEED_URL="${SPARKLE_FEED_URL}" \
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY}" \
  ./pkgbuild.sh

[ -f "${PKG_PATH}" ] || fail "pkgbuild did not create ${PKG_PATH}"

sign_update="$(find_sign_update)"
signature_attributes="$("${sign_update}" "${PKG_PATH}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[ -n "${signature_attributes}" ] || fail "sign_update did not output Sparkle signature attributes"

pkg_asset_name="$(basename "${PKG_PATH}")"
pkg_url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${tag_name}/${pkg_asset_name}"
pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
mkdir -p "$(dirname "${APPCAST_PATH}")"

if [ "${release_kind}" = "stable" ]; then
  release_title="azooKey ${marketing_version}"
  sparkle_short_version="${marketing_version}"
  gh_release_flags=(--latest)
elif [ "${release_kind}" = "pre" ]; then
  release_title="azooKey ${marketing_version} pre-release ${build_version}"
  sparkle_short_version="${marketing_version}-pre.${build_version}"
  gh_release_flags=(--prerelease --latest=false)
else
  release_title="azooKey ${marketing_version} update test ${build_version}"
  sparkle_short_version="${marketing_version}-test.${build_version}"
  gh_release_flags=(--prerelease --latest=false)
fi

cat > "${APPCAST_PATH}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>azooKey for macOS</title>
    <link>https://github.com/$(xml_escape "${GITHUB_REPOSITORY}")</link>
    <description>azooKey for macOS updates</description>
    <language>ja</language>
    <item>
      <title>$(xml_escape "${release_title}")</title>
      <sparkle:version>$(xml_escape "${build_version}")</sparkle:version>
      <sparkle:shortVersionString>$(xml_escape "${sparkle_short_version}")</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <pubDate>${pub_date}</pubDate>
      <enclosure
        url="$(xml_escape "${pkg_url}")"
        ${signature_attributes}
        sparkle:installationType="package"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

if [ "${release_kind}" = "test" ]; then
  git tag -fa "${tag_name}" -m "${release_title}"
  git push --force "${GIT_REMOTE}" "${tag_name}"
  if gh release view "${tag_name}" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
    gh release edit "${tag_name}" \
      --repo "${GITHUB_REPOSITORY}" \
      --title "${release_title}" \
      --prerelease
    gh release upload "${tag_name}" "${PKG_PATH}" "${APPCAST_PATH}#appcast.xml" --repo "${GITHUB_REPOSITORY}" --clobber
  else
    gh release create "${tag_name}" \
      "${PKG_PATH}" \
      "${APPCAST_PATH}#appcast.xml" \
      --repo "${GITHUB_REPOSITORY}" \
      --verify-tag \
      --title "${release_title}" \
      --notes "自動アップデート検証用の固定feedです。" \
      "${gh_release_flags[@]}"
  fi
else
  git tag -a "${tag_name}" -m "${release_title}"
  git push "${GIT_REMOTE}" "${tag_name}"

  gh release create "${tag_name}" \
    "${PKG_PATH}" \
    "${APPCAST_PATH}#appcast.xml" \
    --repo "${GITHUB_REPOSITORY}" \
    --verify-tag \
    --title "${release_title}" \
    --generate-notes \
    "${gh_release_flags[@]}"
fi

echo "Created ${release_kind} release ${tag_name}"
