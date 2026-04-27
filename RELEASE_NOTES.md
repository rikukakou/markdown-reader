# Release Notes

## Markdown Reader v1.1.0

### Added

- Native macOS Markdown reader app bundle
- Native Windows Markdown reader app
- Folder-based recursive Markdown scanning
- Sidebar directory tree for navigating document collections
- Search by file name and relative path
- Drag-and-drop folder opening
- Custom app icon packaging
- Windows build scripts for portable and standalone exe packages
- Generated heading outline for easier document navigation
- Preview copy support and zoom controls on Windows

### Improved

- Wider preview layout for better reading on large windows
- Better Markdown rendering for:
  - headings
  - blockquotes
  - tables
  - task lists
  - code blocks
  - links

### Packaging

- Portable Windows package with repo-local Python dependencies
- Standalone Windows `.exe` package built with PyInstaller
- Auto-generated Windows `.ico` icon from the shared app artwork

### Build

- Build script that produces a standalone macOS `.app`
- Release-ready zip archive for GitHub Releases
- Windows packaging scripts:
  - `build_windows.ps1`
  - `build_windows_exe.ps1`

### Installation Note

Because the app is not notarized with an Apple Developer ID yet, macOS may warn that it cannot verify the app.

If that happens:

1. Move `Markdown Reader.app` to `/Applications`
2. Open `System Settings > Privacy & Security`
3. Find the blocked app message
4. Click `Open Anyway` / `仍要打开`
5. Confirm the second open dialog
