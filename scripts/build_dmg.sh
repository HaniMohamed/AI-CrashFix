#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist"
MACOS_DIR="${OUT_DIR}/macos"
APP_NAME="AI Crash Fix.app"
APP_PATH="${MACOS_DIR}/${APP_NAME}"
DMG_PATH="${OUT_DIR}/AI-Crash-Fix.dmg"
DMG_VOLNAME="AI Crash Fix"
DMG_BG_SVG="${ROOT_DIR}/packaging/macos/dmg_background.svg"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing app bundle at: ${APP_PATH}"
  echo "Run: scripts/build_macos_app.sh"
  exit 1
fi

rm -f "${DMG_PATH}"

STAGE_DIR="${OUT_DIR}/.dmg-stage"
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"

cp -R "${APP_PATH}" "${STAGE_DIR}/${APP_NAME}"
ln -s "/Applications" "${STAGE_DIR}/Applications"

# Create a read-write DMG we can customize (window size, icon layout, background).
BASE_DMG="${OUT_DIR}/.tmp-ai-crash-fix-base.dmg"
RW_DMG="${OUT_DIR}/.tmp-ai-crash-fix-rw.dmg"
RO_DMG="${OUT_DIR}/.tmp-ai-crash-fix-ro.dmg"
rm -f "${BASE_DMG}" "${RW_DMG}" "${RO_DMG}"

# Some macOS versions fail when creating UDRW directly from -srcfolder.
# Create a compressed image first, then convert to read-write for customization.
hdiutil create \
  -volname "${DMG_VOLNAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${BASE_DMG}" >/dev/null

hdiutil convert "${BASE_DMG}" -format UDRW -ov -o "${RW_DMG}" >/dev/null
rm -f "${BASE_DMG}"

cleanup() {
  rm -rf "${STAGE_DIR}"
  rm -f "${RO_DMG}"
  rm -f "${BASE_DMG}"
  # Best-effort cleanup if a previous run left the image mounted.
  hdiutil detach "${RW_DMG}" -force -quiet >/dev/null 2>&1 || true
}
trap cleanup EXIT

customize_dmg() {
  # Customization can fail on headless environments; keep a fallback.
  command -v osascript >/dev/null 2>&1 || return 1
  command -v qlmanage >/dev/null 2>&1 || return 1

  # Attach and grab device + mount point. We detach by *device* (more reliable).
  local attach_out mount_point device
  attach_out="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")"
  mount_point="$(echo "${attach_out}" | awk '/\/Volumes\// {print $NF; exit}')"
  device="$(echo "${attach_out}" | awk '/\/Volumes\// {print $1; exit}')"
  [[ -n "${mount_point}" ]] || return 1
  [[ -n "${device}" ]] || return 1

  # Background image
  mkdir -p "${mount_point}/.background"
  if [[ -f "${DMG_BG_SVG}" ]]; then
    local tmp_dir png
    tmp_dir="${OUT_DIR}/.tmp-dmg-bg"
    rm -rf "${tmp_dir}"
    mkdir -p "${tmp_dir}"
    qlmanage -t -s 1360 -o "${tmp_dir}" "${DMG_BG_SVG}" >/dev/null 2>&1 || true
    png="$(ls -1 "${tmp_dir}"/*.png 2>/dev/null | head -n 1 || true)"
    if [[ -n "${png}" ]]; then
      cp "${png}" "${mount_point}/.background/background.png"
    fi
    rm -rf "${tmp_dir}"
  fi

  # Finder layout
  # Coordinates are tuned for a compact DMG window on modern macOS.
  # We delay between Finder operations to avoid race conditions.
  osascript >/dev/null <<OSA || true
tell application "Finder"
  tell disk "${DMG_VOLNAME}"
    open
    delay 0.8
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {220, 140, 800, 460}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 12

    try
      set bgFile to file ".background:background.png"
      set background picture of viewOptions to bgFile
    end try

    try
      set position of item "${APP_NAME}" to {130, 200}
    end try
    try
      set position of item "Applications" to {450, 200}
    end try
    try
      set position of item "Applications.alias" to {450, 200}
    end try

    close
    open
    update without registering applications
    delay 1.2
  end tell
end tell
OSA

  # Give Finder time to write .DS_Store.
  sleep 2

  # Ensure Finder releases the volume before converting.
  osascript >/dev/null <<OSA || true
tell application "Finder"
  try
    close (every window whose name is "${DMG_VOLNAME}")
  end try
end tell
OSA
  sleep 1

  hdiutil detach "${device}" -quiet || true
  hdiutil detach "${device}" -force -quiet || true
  return 0
}

customize_dmg || true

# Ensure the RW image isn't still mounted (best-effort).
if hdiutil info 2>/dev/null | grep -Fq "${RW_DMG}"; then
  hdiutil detach "${RW_DMG}" -force -quiet >/dev/null 2>&1 || true
fi

# Convert to compressed read-only DMG
hdiutil convert "${RW_DMG}" -format UDZO -ov -o "${RO_DMG}" >/dev/null
mv "${RO_DMG}" "${DMG_PATH}"
rm -f "${RW_DMG}"

# Optional: mark as "internet-enabled" (shows nicer name in Safari)
hdiutil internet-enable -yes "${DMG_PATH}" >/dev/null 2>&1 || true

echo "DMG created at: ${DMG_PATH}"
