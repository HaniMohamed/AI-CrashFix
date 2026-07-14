# Legacy Swift menubar launcher (unused)

The DMG pipeline now ships a **Flutter macOS** Dock app that embeds the
backend and stops it on quit. See [`docs/macos_packaging.md`](../../../docs/macos_packaging.md).

This launcher (LSUIElement tray + open system browser) is kept only as
reference and is **not** invoked by `scripts/build_macos_app.sh` /
`scripts/build_macos_dmg_all.sh`.
