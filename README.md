# Markdown Reader for macOS

A small native macOS app for scanning and reading Markdown documents in a folder.

## Features

- Choose one folder and auto-scan all `.md` and `.markdown` files inside it
- Sidebar directory tree for quick switching between documents
- Search files by name or relative path
- HTML preview with full-width layout and better heading, list, quote, link, table, task-list, and code-block formatting
- Drag and drop a folder directly into the window
- Custom macOS app icon generated for this app and bundled during build
- Native AppKit window for macOS
- Build into a standalone `.app`

## Build

Run:

```bash
chmod +x build.sh
./build.sh
```

After the build finishes, the app bundle will be here:

```bash
/Users/jiahao/Documents/Codex/2026-04-24-markdown-mac/build/Markdown Reader.app
```

You can then move it into `/Applications` if you want.

## Icon

The build also packages the icon source at `Assets/AppIconSource.png` into `AppIcon.icns` automatically via `scripts/generate_icon.py`.
