# Markdown Reader

A desktop app for scanning, organizing, and reading Markdown documents from a folder.

![Markdown Reader preview](docs/app-preview.png)

## Highlights

- Open one folder and recursively scan all `.md` and `.markdown` files
- Browse documents with a sidebar directory tree
- Search files by name or relative path
- Read Markdown in a clean preview pane
- Better rendering for headings, lists, blockquotes, tables, task lists, code blocks, and links
- Native desktop implementations for both macOS and Windows
- Custom app icon source included in the repo

## Why This App

Markdown Reader is designed for local documentation sets, notes collections, and project folders where you want:

- A lightweight desktop reader instead of a browser-heavy workflow
- Fast folder-based browsing without importing files into a database
- A readable preview for structured Markdown documents

## Platforms

### macOS

The original app is a native AppKit application written in Objective-C.

Build:

Run:

```bash
chmod +x build.sh
./build.sh
```

After the build finishes, the app bundle will be created at:

```bash
/Users/jiahao/Documents/Codex/2026-04-24-markdown-mac/build/Markdown Reader.app
```

The build also creates a release-ready zip archive at:

```bash
/Users/jiahao/Documents/Codex/2026-04-24-markdown-mac/build/Markdown-Reader-macOS.zip
```

You can move the `.app` to `/Applications`, or upload the `.zip` file to a GitHub Release.

### Windows

The Windows app lives in `Windows/markdown_reader.pyw` and is implemented with Python + Tkinter. It prefers repo-local dependencies from `.tools\python-deps`, so Markdown parsing stays consistent without requiring a global Python setup.

Run locally:

```powershell
.\run_windows.cmd
```

Open a folder immediately:

```powershell
.\run_windows.cmd C:\path\to\docs
```

The app supports:

- Recursive Markdown scanning
- Sidebar directory tree
- File search
- Styled preview for headings, lists, task lists, tables, quotes, code blocks, and links
- Local file links and web links

Build a portable Windows package:

```powershell
.\build_windows.ps1
```

That script creates:

```text
build\Markdown-Reader-Windows\
build\Markdown-Reader-Windows-portable.zip
```

Build a standalone Windows `.exe` package:

```powershell
.\build_windows_exe.ps1
```

That script creates:

```text
build\exe\Markdown Reader\Markdown Reader.exe
build\Markdown-Reader-Windows-exe.zip
```

The exe build uses PyInstaller and auto-generates a Windows `.ico` file from `Assets/AppIconSource.png`. If the required Python packages are not already available, the script installs them into `.tools\pyinstaller` and `.tools\python-deps` inside this repository.

## First Launch on macOS

Because the app is not notarized with an Apple Developer ID yet, macOS may block it the first time you open it.

If you see a warning, open:

`System Settings > Privacy & Security`

Then find the blocked app notice and click `Open Anyway` / `仍要打开`.

![macOS open anyway guidance](docs/macos-open-anyway.png)

Recommended steps:

1. Download and unzip the release
2. Move `Markdown Reader.app` to `/Applications`
3. Try opening the app once
4. If macOS blocks it, go to `System Settings > Privacy & Security`
5. Click `Open Anyway` / `仍要打开`
6. Return to the app and confirm `Open`

## Project Structure

- `App/main.m`: main macOS app implementation
- `Windows/markdown_reader.pyw`: main Windows app implementation
- `build.sh`: macOS build script for producing the `.app`
- `build_windows.ps1`: Windows portable packaging script
- `build_windows_exe.ps1`: Windows executable packaging script
- `run_windows.cmd`: Windows launcher
- `Assets/AppIconSource.png`: source artwork for the app icon
- `scripts/generate_icon.py`: generates the `.icns` file used by macOS
- `Resources/Info.plist`: app bundle metadata

## Current Features

- Folder-based Markdown library scanning
- Sidebar navigation tree
- File search
- Markdown preview with headings, tables, task lists, quotes, and code blocks
- Native desktop builds for macOS and Windows

## Notes

- The macOS app is a native AppKit application written in Objective-C
- The Windows app is a native Tkinter desktop app written in Python
- Generated build artifacts are excluded from git
- Release notes are available in `RELEASE_NOTES.md`
