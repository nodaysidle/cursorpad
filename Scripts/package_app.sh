#!/bin/bash
#
# CursorPad packaging authority — CON-PACKAGING-RELEASE (PHASE-09).
#
# Sole authority for the release build, .app assembly, resources, signing, strict
# verification and DMG creation:
#
#   1. swift build -c release --arch arm64      (a failed build is fatal)
#   2. swift build -c release --arch arm64 --show-bin-path   (release executable path)
#   3. reject any release executable that is not a Mach-O arm64 binary
#   4. assemble dist/CursorPad.app/Contents/{MacOS,Resources}
#   5. codesign with Resources/App.entitlements, then codesign --verify --deep --strict
#   6. create and verify dist/CursorPad.dmg with hdiutil
#
# Signing identity: ad-hoc "-" by default (local proof). A distribution identity is
# supplied explicitly through the environment, for example
#   CURSORPAD_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" Scripts/package_app.sh
#
# Installing into /Applications and launching through LaunchServices is opt-in only and
# never happens on a default run: pass --install to request it.
#
# Usage:
#   Scripts/package_app.sh [--install]
#   Scripts/package_app.sh --help

set -euo pipefail

readonly APP_NAME="CursorPad"
readonly EXECUTABLE_NAME="Cursorpad"
readonly BUNDLE_IDENTIFIER="com.cursorpad.app"
readonly BUNDLE_VERSION="1.0.0"
readonly BUNDLE_BUILD="1"
readonly MINIMUM_SYSTEM_VERSION="14.0"
readonly ICON_NAME="AppIcon"
readonly PACKAGE_TYPE="APPL"
readonly PKGINFO_CONTENT="APPL????"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ROOT_DIR

readonly DIST_DIR="${ROOT_DIR}/dist"
readonly APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
readonly DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
readonly STAGING_DIR="${DIST_DIR}/dmg-staging"
readonly EXPECTED_APP_PATH="dist/CursorPad.app"
readonly EXPECTED_DMG_PATH="dist/CursorPad.dmg"

readonly INFOPLIST_SRC="${ROOT_DIR}/Resources/Info.plist"
readonly ENTITLEMENTS_SRC="${ROOT_DIR}/Resources/App.entitlements"
readonly ICON_SRC="${ROOT_DIR}/Resources/AppIcon.icns"
readonly USERGUIDE_SRC="${ROOT_DIR}/USERGUIDE.md"

readonly PLIST_BUDDY="/usr/libexec/PlistBuddy"

CURSORPAD_INSTALL=0

log() { printf '[package_app] %s\n' "$*" >&2; }
fatal() { printf '[package_app] fatal: %s\n' "$*" >&2; exit 1; }

usage() {
	cat <<'USAGE'
Package CursorPad: release build, .app assembly, ad-hoc or Developer ID signing,
strict codesign verification and DMG creation.

Usage: Scripts/package_app.sh [--install]

  (no options)  build, assemble dist/CursorPad.app, sign, verify, create dist/CursorPad.dmg
  --install     additionally copy the verified app to /Applications after a scoped
                rollback copy, register it with LaunchServices and launch it
  -h, --help    show this help

Environment:
  CURSORPAD_SIGN_IDENTITY   codesign identity to use; "-" (ad-hoc) when unset
USAGE
}

for argument in "$@"; do
	case "${argument}" in
		--install) CURSORPAD_INSTALL=1 ;;
		-h|--help) usage; exit 0 ;;
		*) fatal "unknown argument '${argument}' (try --help)" ;;
	esac
done

for required_input in "${INFOPLIST_SRC}" "${ENTITLEMENTS_SRC}" "${ICON_SRC}" "${USERGUIDE_SRC}"; do
	[[ -f "${required_input}" ]] || fatal "missing required packaging input: ${required_input}"
done

for required_tool in swift codesign hdiutil lipo file; do
	command -v "${required_tool}" >/dev/null 2>&1 || fatal "missing required tool: ${required_tool}"
done

[[ -x "${PLIST_BUDDY}" ]] || fatal "missing required tool: ${PLIST_BUDDY}"

# The locked artifact layout (AGENTS.md "Artifact path") is asserted, not assumed.
[[ "${APP_BUNDLE}" == "${ROOT_DIR}/${EXPECTED_APP_PATH}" ]] || fatal "app bundle path drifted from ${EXPECTED_APP_PATH}"
[[ "${DMG_PATH}" == "${ROOT_DIR}/${EXPECTED_DMG_PATH}" ]] || fatal "disk image path drifted from ${EXPECTED_DMG_PATH}"

# 1. Release build. A failed build is fatal — packaging never continues past it.
log "release build: swift build -c release --arch arm64"
if ! swift build -c release --arch arm64; then
	fatal "release build failed — packaging aborted"
fi

# 2. Release executable path, asked of SwiftPM itself.
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
[[ -n "${BIN_DIR}" ]] || fatal "swift build --show-bin-path returned an empty path"
EXECUTABLE_PATH="${BIN_DIR}/${EXECUTABLE_NAME}"
if [[ ! -f "${EXECUTABLE_PATH}" && -f "${ROOT_DIR}/.build/arm64-apple-macosx/release/${EXECUTABLE_NAME}" ]]; then
	EXECUTABLE_PATH="${ROOT_DIR}/.build/arm64-apple-macosx/release/${EXECUTABLE_NAME}"
	log "note: using legacy release layout ${EXECUTABLE_PATH}"
fi
[[ -f "${EXECUTABLE_PATH}" ]] || fatal "release executable not found at ${EXECUTABLE_PATH}"
log "release executable: ${EXECUTABLE_PATH}"

# 3. The release executable must be a thin Mach-O arm64 binary.
MACHO_DESCRIPTION="$(file -b "${EXECUTABLE_PATH}")"
case "${MACHO_DESCRIPTION}" in
	*"Mach-O 64-bit executable arm64"*) log "Mach-O arm64 verified: ${MACHO_DESCRIPTION}" ;;
	*) fatal "release executable is not a Mach-O arm64 executable: ${MACHO_DESCRIPTION}" ;;
esac
ARCHITECTURES="$(lipo -archs "${EXECUTABLE_PATH}")"
[[ "${ARCHITECTURES}" == "arm64" ]] || fatal "release executable must be arm64 only, found: ${ARCHITECTURES}"

# 4. Assemble the bundle.
log "assembling ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

install -m 755 "${EXECUTABLE_PATH}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
install -m 644 "${INFOPLIST_SRC}" "${APP_BUNDLE}/Contents/Info.plist"
install -m 644 "${ICON_SRC}" "${APP_BUNDLE}/Contents/Resources/${ICON_NAME}.icns"
install -m 644 "${USERGUIDE_SRC}" "${APP_BUNDLE}/Contents/Resources/USERGUIDE.md"
install -m 644 "${ENTITLEMENTS_SRC}" "${APP_BUNDLE}/Contents/Resources/App.entitlements"
printf '%s' "${PKGINFO_CONTENT}" > "${APP_BUNDLE}/Contents/PkgInfo"

PKGINFO_TEXT="$(<"${APP_BUNDLE}/Contents/PkgInfo")"
[[ "${PKGINFO_TEXT}" == "${PKGINFO_CONTENT}" ]] || fatal "Contents/PkgInfo must contain exactly ${PKGINFO_CONTENT}"
[[ "$(wc -c < "${APP_BUNDLE}/Contents/PkgInfo" | tr -d '[:space:]')" == "8" ]] || fatal "Contents/PkgInfo must be exactly 8 bytes"

# 5. Pre-signing identity gate, read back from the assembled bundle itself.
check_plist_value() {
	local actual
	actual="$("${PLIST_BUDDY}" -c "Print :$1" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null)" \
		|| fatal "Info.plist is missing key $1"
	[[ "${actual}" == "$2" ]] || fatal "Info.plist $1 must be '$2', found '${actual}'"
}

check_plist_value CFBundleIdentifier "${BUNDLE_IDENTIFIER}"
check_plist_value CFBundleName "${APP_NAME}"
check_plist_value CFBundleExecutable "${EXECUTABLE_NAME}"
check_plist_value CFBundleIconFile "${ICON_NAME}"
check_plist_value CFBundlePackageType "${PACKAGE_TYPE}"
check_plist_value CFBundleShortVersionString "${BUNDLE_VERSION}"
check_plist_value CFBundleVersion "${BUNDLE_BUILD}"
check_plist_value LSMinimumSystemVersion "${MINIMUM_SYSTEM_VERSION}"
log "bundle identity verified: ${BUNDLE_IDENTIFIER} ${BUNDLE_VERSION} (${BUNDLE_BUILD}), minimum macOS ${MINIMUM_SYSTEM_VERSION}"

SIGN_IDENTITY="${CURSORPAD_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "${SIGN_IDENTITY}" --entitlements "${ENTITLEMENTS_SRC}")
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
	SIGN_ARGS+=(--timestamp=none)
else
	SIGN_ARGS+=(--options runtime --timestamp)
fi
log "codesign (identity: ${SIGN_IDENTITY}, entitlements: Resources/App.entitlements)"
codesign "${SIGN_ARGS[@]}" "${APP_BUNDLE}"

# Mandatory gate: strict verification must pass before DMG creation.
log "codesign --verify --deep --strict --verbose=2 ${APP_BUNDLE}"
if ! codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"; then
	fatal "codesign strict verification failed"
fi
log "codesign strict verification passed"

# 6. DMG staging (app + the conventional /Applications drop target), then create and verify.
log "hdiutil create ${DMG_PATH}"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"
ditto "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
# Deterministic enough: fixed volume name, single staging root and pinned timestamps, so the
# same verified bundle always produces the same image layout.
find "${STAGING_DIR}" -exec touch -h -t 202401010000.00 {} +
hdiutil create -quiet -fs HFS+ -format UDZO -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov "${DMG_PATH}"
rm -rf "${STAGING_DIR}"

[[ -f "${DMG_PATH}" ]] || fatal "DMG was not created at ${DMG_PATH}"
log "hdiutil verify ${DMG_PATH}"
if ! hdiutil verify "${DMG_PATH}"; then
	fatal "DMG verification failed"
fi
log "DMG verified"

log "done"
log "app: ${APP_BUNDLE}"
log "dmg: ${DMG_PATH}"

if [[ "${CURSORPAD_INSTALL}" == "1" ]]; then
	readonly INSTALL_TARGET="/Applications/${APP_NAME}.app"
	readonly ROLLBACK_DIR="${DIST_DIR}/install-rollback"
	readonly LAUNCH_SERVICES_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

	log "install: scoped rollback copy of ${INSTALL_TARGET}"
	mkdir -p "${ROLLBACK_DIR}"
	if [[ -d "${INSTALL_TARGET}" ]]; then
		rm -rf "${ROLLBACK_DIR:?}/${APP_NAME}.app"
		ditto "${INSTALL_TARGET}" "${ROLLBACK_DIR}/${APP_NAME}.app"
	fi

	log "install: copying ${APP_BUNDLE} to ${INSTALL_TARGET}"
	rm -rf "${INSTALL_TARGET:?}"
	ditto "${APP_BUNDLE}" "${INSTALL_TARGET}"
	if ! codesign --verify --deep --strict "${INSTALL_TARGET}"; then
		fatal "installed bundle failed strict verification"
	fi

	if [[ -x "${LAUNCH_SERVICES_REGISTER}" ]]; then
		"${LAUNCH_SERVICES_REGISTER}" -f "${INSTALL_TARGET}"
	fi

	# Launch and confirm the running bundle identity (not a path lookalike).
	open -b "${BUNDLE_IDENTIFIER}"
	sleep 2
	RUNNING_PATH=""
	if ! RUNNING_PATH="$(osascript -e "POSIX path of (path to application id \"${BUNDLE_IDENTIFIER}\")" 2>/dev/null)"; then
		RUNNING_PATH=""
	fi
	# LaunchServices reports the bundle with a trailing slash. Compare the directory, not the punctuation.
	RUNNING_PATH="${RUNNING_PATH%/}"
	[[ "${RUNNING_PATH}" == "${INSTALL_TARGET}" ]] || fatal "LaunchServices resolved ${BUNDLE_IDENTIFIER} to '${RUNNING_PATH}', expected ${INSTALL_TARGET}"
	log "installed and launched: ${INSTALL_TARGET}"
fi

exit 0
