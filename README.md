# Markdown Reader for macOS

A native macOS app for scanning, organizing, and reading Markdown documents from a folder.

![Markdown Reader preview](docs/app-preview.png)

## Highlights

- Open one folder and recursively scan all `.md` and `.markdown` files
- Browse documents with a sidebar directory tree
- Search files by name or relative path
- Read Markdown in a clean full-width preview pane
- Better rendering for headings, lists, blockquotes, tables, task lists, and code blocks
- Drag a folder directly into the app window
- Native macOS app bundle with a custom app icon

## Why This App

Markdown Reader is designed for local documentation sets, notes collections, and project folders where you want:

- A lightweight native macOS reader instead of a browser-heavy workflow
- Fast folder-based browsing without importing files into a database
- A readable preview for structured Markdown documents

## Build

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
- `build.sh`: build script for producing the `.app`
- `Assets/AppIconSource.png`: source artwork for the app icon
- `scripts/generate_icon.py`: generates the `.icns` file used by macOS
- `Resources/Info.plist`: app bundle metadata

## Current Features

- Folder-based Markdown library scanning
- Sidebar navigation tree
- File search
- Drag-and-drop folder opening
- Native app icon packaging
- Standalone `.app` output

## Notes

- This is a native AppKit application written in Objective-C
- The preview is HTML-based for better Markdown styling flexibility
- Generated build artifacts are excluded from git
- Release notes are available in `RELEASE_NOTES.md`
