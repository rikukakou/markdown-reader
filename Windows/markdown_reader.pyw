from __future__ import annotations

import argparse
from html.parser import HTMLParser
import locale
import os
import re
import sys
import webbrowser
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Iterable

import tkinter as tk
from tkinter import filedialog, font, ttk


REPO_ROOT = Path(__file__).resolve().parent.parent
LOCAL_DEPENDENCY_DIR = REPO_ROOT / ".tools" / "python-deps"
if LOCAL_DEPENDENCY_DIR.exists():
    sys.path.insert(0, str(LOCAL_DEPENDENCY_DIR))

try:
    import markdown as markdown_lib
except ImportError:
    markdown_lib = None


APP_NAME = "Markdown Reader"
WINDOW_WIDTH = 1280
WINDOW_HEIGHT = 800
SIDEBAR_WIDTH = 340
SUPPORTED_EXTENSIONS = {".md", ".markdown"}
INLINE_PATTERN = re.compile(
    r"!\[([^\]]*)\]\(([^)]+)\)"
    r"|\[([^\]]+)\]\(([^)]+)\)"
    r"|`([^`]+)`"
    r"|\*\*([^*]+)\*\*"
    r"|__([^_]+)__"
    r"|(?<!\*)\*([^*\n]+)\*(?!\*)"
    r"|(?<!_)_([^_\n]+)_(?!_)"
)
ORDERED_LIST_PATTERN = re.compile(r"^([0-9]+)\.\s+(.+)$")
TASK_LIST_PATTERN = re.compile(r"^[-*]\s+\[([ xX])\]\s+(.+)$")


def resource_path(relative_path: str) -> Path:
    root = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
    return root / relative_path


@dataclass
class FileNode:
    name: str
    relative_path: str
    file_path: Path | None = None
    directory: bool = False
    children: list["FileNode"] = field(default_factory=list)

    def is_leaf(self) -> bool:
        return not self.directory


@dataclass
class HeadingEntry:
    level: int
    title: str
    text_index: str


class MarkdownRenderer:
    def __init__(self, text_widget: tk.Text) -> None:
        self.text_widget = text_widget
        self.base_dir: Path | None = None
        self.headings: list[HeadingEntry] = []
        self.link_index = 0
        self.zoom_percent = 100
        self._configure_tags()

    def _configure_tags(self) -> None:
        base_font = font.nametofont("TkDefaultFont")
        self.base_font_family = base_font.actual("family")
        mono_family = "Consolas" if "Consolas" in font.families() else "Courier New"
        self.mono_font_family = mono_family
        self._apply_zoom()

    def _scaled_size(self, size: int) -> int:
        return max(8, round(size * self.zoom_percent / 100))

    def _apply_zoom(self) -> None:
        base_family = self.base_font_family
        mono_family = self.mono_font_family

        self.heading_fonts = {
            1: font.Font(family=base_family, size=self._scaled_size(22), weight="bold"),
            2: font.Font(family=base_family, size=self._scaled_size(18), weight="bold"),
            3: font.Font(family=base_family, size=self._scaled_size(16), weight="bold"),
            4: font.Font(family=base_family, size=self._scaled_size(14), weight="bold"),
            5: font.Font(family=base_family, size=self._scaled_size(13), weight="bold"),
            6: font.Font(family=base_family, size=self._scaled_size(12), weight="bold"),
        }
        self.strong_font = font.Font(family=base_family, size=self._scaled_size(11), weight="bold")
        self.emphasis_font = font.Font(
            family=base_family, size=self._scaled_size(11), slant="italic"
        )
        self.body_font = font.Font(family=base_family, size=self._scaled_size(11))
        self.code_font = font.Font(family=mono_family, size=self._scaled_size(10))

        self.text_widget.configure(
            bg="#fffdf8",
            fg="#1f2328",
            insertbackground="#1f2328",
            wrap="word",
            takefocus=1,
            exportselection=True,
            font=self.body_font,
            padx=24,
            pady=18,
            spacing1=3,
            spacing3=7,
        )
        self.text_widget.tag_configure("paragraph", spacing1=2, spacing3=10)
        self.text_widget.tag_configure("muted", foreground="#6b7280")
        self.text_widget.tag_configure("strong", font=self.strong_font)
        self.text_widget.tag_configure("emphasis", font=self.emphasis_font)
        self.text_widget.tag_configure(
            "inline_code",
            font=self.code_font,
            background="#efe7da",
            foreground="#7c2d12",
        )
        self.text_widget.tag_configure(
            "code_block",
            font=self.code_font,
            background="#efe7da",
            foreground="#111827",
            lmargin1=24,
            lmargin2=24,
            rmargin=16,
            spacing1=8,
            spacing3=10,
        )
        self.text_widget.tag_configure(
            "blockquote",
            foreground="#6b4f39",
            background="#f4d7bf",
            lmargin1=18,
            lmargin2=30,
            rmargin=12,
            spacing1=4,
            spacing3=8,
        )
        self.text_widget.tag_configure(
            "list_item", lmargin1=16, lmargin2=38, spacing1=1, spacing3=1
        )
        self.text_widget.tag_configure(
            "table",
            font=self.code_font,
            background="#f8f4ed",
            lmargin1=12,
            lmargin2=12,
            spacing1=2,
            spacing3=4,
        )
        self.text_widget.tag_configure("hr", foreground="#b4a693")
        self.text_widget.tag_configure("title", foreground="#111827", spacing3=12)
        self.text_widget.tag_configure("link", foreground="#9a3412", underline=True)

        for level, heading_font in self.heading_fonts.items():
            self.text_widget.tag_configure(
                f"heading_{level}", font=heading_font, spacing1=12, spacing3=6
            )

    def zoom_in(self) -> None:
        self.set_zoom(self.zoom_percent + 10)

    def zoom_out(self) -> None:
        self.set_zoom(self.zoom_percent - 10)

    def reset_zoom(self) -> None:
        self.set_zoom(100)

    def set_zoom(self, percent: int) -> None:
        clamped = max(70, min(220, percent))
        if clamped == self.zoom_percent:
            return
        self.zoom_percent = clamped
        self._apply_zoom()

    def render(self, markdown_text: str, title: str, base_dir: Path | None) -> None:
        self.base_dir = base_dir
        self.headings = []
        self.link_index = 0
        text = self.text_widget
        text.configure(state="normal")
        text.delete("1.0", "end")

        if markdown_lib is not None:
            html = markdown_lib.markdown(
                self._normalize_task_lists(markdown_text),
                extensions=[
                    "markdown.extensions.extra",
                    "markdown.extensions.sane_lists",
                    "markdown.extensions.nl2br",
                ],
                output_format="html5",
            )
            HTMLTextRenderer(self).feed(html)
            text.configure(state="disabled")
            return

        lines = markdown_text.splitlines()
        index = 0
        in_code_block = False
        code_lines: list[str] = []

        while index < len(lines):
            raw_line = lines[index]
            stripped = raw_line.strip()

            if stripped.startswith("```"):
                if in_code_block:
                    self._insert_code_block(code_lines)
                    code_lines.clear()
                    in_code_block = False
                else:
                    in_code_block = True
                index += 1
                continue

            if in_code_block:
                code_lines.append(raw_line)
                index += 1
                continue

            if not stripped:
                self._insert_newline()
                index += 1
                continue

            if self._is_horizontal_rule(stripped):
                self.text_widget.insert("end", "─" * 72 + "\n", ("hr",))
                self._insert_newline()
                index += 1
                continue

            if self._looks_like_table(lines, index):
                consumed = self._insert_table(lines, index)
                index += consumed
                continue

            if stripped.startswith("#"):
                consumed = len(stripped) - len(stripped.lstrip("#"))
                level = max(1, min(6, consumed))
                content = stripped[level:].strip()
                heading_index = self.text_widget.index("end-1c")
                self.headings.append(HeadingEntry(level=level, title=content, text_index=heading_index))
                self._insert_inline_text(content, (f"heading_{level}", "title"))
                self.text_widget.insert("end", "\n")
                self._insert_newline()
                index += 1
                continue

            if stripped.startswith(">"):
                quote_lines: list[str] = []
                while index < len(lines) and lines[index].strip().startswith(">"):
                    quote_lines.append(lines[index].strip()[1:].strip())
                    index += 1
                for quote_line in quote_lines:
                    self.text_widget.insert("end", "▎ ", ("blockquote",))
                    self._insert_inline_text(quote_line, ("blockquote",))
                    self.text_widget.insert("end", "\n")
                self._insert_newline()
                continue

            task_match = TASK_LIST_PATTERN.match(stripped)
            if task_match:
                checked = task_match.group(1).lower() == "x"
                self.text_widget.insert(
                    "end", f"{'☑' if checked else '☐'} ", ("list_item",)
                )
                self._insert_inline_text(task_match.group(2), ("list_item",))
                self.text_widget.insert("end", "\n")
                index += 1
                continue

            if stripped.startswith("- ") or stripped.startswith("* "):
                self.text_widget.insert("end", "• ", ("list_item",))
                self._insert_inline_text(stripped[2:].strip(), ("list_item",))
                self.text_widget.insert("end", "\n")
                index += 1
                continue

            ordered_match = ORDERED_LIST_PATTERN.match(stripped)
            if ordered_match:
                self.text_widget.insert("end", f"{ordered_match.group(1)}. ", ("list_item",))
                self._insert_inline_text(ordered_match.group(2), ("list_item",))
                self.text_widget.insert("end", "\n")
                index += 1
                continue

            paragraph_lines = [stripped]
            index += 1
            while index < len(lines):
                probe = lines[index].strip()
                if not probe:
                    break
                if (
                    probe.startswith("#")
                    or probe.startswith(">")
                    or probe.startswith("```")
                    or probe.startswith("- ")
                    or probe.startswith("* ")
                    or TASK_LIST_PATTERN.match(probe)
                    or ORDERED_LIST_PATTERN.match(probe)
                    or self._looks_like_table(lines, index)
                    or self._is_horizontal_rule(probe)
                ):
                    break
                paragraph_lines.append(probe)
                index += 1

            self._insert_inline_text(" ".join(paragraph_lines), ("paragraph",))
            self.text_widget.insert("end", "\n")
            self._insert_newline()

        if in_code_block and code_lines:
            self._insert_code_block(code_lines)

        self.text_widget.configure(state="disabled")

    def _normalize_task_lists(self, markdown_text: str) -> str:
        lines = markdown_text.splitlines()
        normalized: list[str] = []
        for line in lines:
            match = re.match(r"^(\s*)[-*]\s+\[([ xX])\]\s+(.+)$", line)
            if match:
                marker = "[x]" if match.group(2).lower() == "x" else "[ ]"
                normalized.append(f"{match.group(1)}- {marker} {match.group(3)}")
            else:
                normalized.append(line)
        return "\n".join(normalized)

    def _insert_code_block(self, lines: list[str]) -> None:
        code = "\n".join(lines).rstrip()
        self.text_widget.insert("end", code + "\n", ("code_block",))
        self._insert_newline()

    def _insert_text(self, content: str, tags: tuple[str, ...] = ()) -> None:
        if not content:
            return
        self.text_widget.insert("end", content, tags)

    def _insert_table(self, lines: list[str], start_index: int) -> int:
        header = self._table_cells(lines[start_index].strip())
        rows: list[list[str]] = []
        row_index = start_index + 2

        while row_index < len(lines):
            row = lines[row_index].strip()
            if not row or "|" not in row:
                break
            rows.append(self._table_cells(row))
            row_index += 1

        widths = [len(self._plain_text(cell)) for cell in header]
        for row in rows:
            for index, cell in enumerate(row):
                if index >= len(widths):
                    widths.append(0)
                widths[index] = max(widths[index], len(self._plain_text(cell)))

        rendered_lines = [
            self._table_row(header, widths),
            self._table_separator(widths),
        ]
        rendered_lines.extend(self._table_row(row, widths) for row in rows)
        self.text_widget.insert("end", "\n".join(rendered_lines) + "\n", ("table",))
        self._insert_newline()
        return row_index - start_index

    def _table_cells(self, line: str) -> list[str]:
        trimmed = line.strip()
        if trimmed.startswith("|"):
            trimmed = trimmed[1:]
        if trimmed.endswith("|"):
            trimmed = trimmed[:-1]
        return [part.strip() for part in trimmed.split("|")]

    def _table_row(self, cells: list[str], widths: list[int]) -> str:
        padded: list[str] = []
        for index, width in enumerate(widths):
            value = self._plain_text(cells[index]) if index < len(cells) else ""
            padded.append(value.ljust(width))
        return " | ".join(padded)

    def _table_separator(self, widths: list[int]) -> str:
        return "-+-".join("-" * width for width in widths)

    def _plain_text(self, value: str) -> str:
        text = value
        text = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r"[Image: \1]", text)
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", text)
        text = re.sub(r"`([^`]+)`", r"\1", text)
        text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
        text = re.sub(r"__([^_]+)__", r"\1", text)
        text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"\1", text)
        text = re.sub(r"(?<!_)_([^_\n]+)_(?!_)", r"\1", text)
        return text

    def _insert_inline_text(
        self, text: str, base_tags: tuple[str, ...] = ()
    ) -> None:
        cursor = 0
        for match in INLINE_PATTERN.finditer(text):
            start, end = match.span()
            if start > cursor:
                self.text_widget.insert("end", text[cursor:start], base_tags)

            if match.group(1) is not None:
                alt_text = match.group(1).strip() or "image"
                target = match.group(2).strip()
                display = f"[Image: {alt_text}]"
                self._insert_link(display, target, base_tags)
            elif match.group(3) is not None:
                self._insert_link(match.group(3), match.group(4), base_tags)
            elif match.group(5) is not None:
                self.text_widget.insert("end", match.group(5), base_tags + ("inline_code",))
            elif match.group(6) is not None:
                self.text_widget.insert("end", match.group(6), base_tags + ("strong",))
            elif match.group(7) is not None:
                self.text_widget.insert("end", match.group(7), base_tags + ("strong",))
            elif match.group(8) is not None:
                self.text_widget.insert("end", match.group(8), base_tags + ("emphasis",))
            elif match.group(9) is not None:
                self.text_widget.insert("end", match.group(9), base_tags + ("emphasis",))

            cursor = end

        if cursor < len(text):
            self.text_widget.insert("end", text[cursor:], base_tags)

    def _insert_link(self, label: str, target: str, base_tags: tuple[str, ...]) -> None:
        start_index = self.text_widget.index("end-1c")
        self.text_widget.insert("end", label, base_tags + ("link",))
        end_index = self.text_widget.index("end-1c")
        self.link_index += 1
        tag_name = f"link_target_{self.link_index}"
        self.text_widget.tag_add(tag_name, start_index, end_index)
        self.text_widget.tag_configure(tag_name, foreground="#9a3412", underline=True)
        self.text_widget.tag_bind(
            tag_name,
            "<Button-1>",
            lambda _event, link=target: self._open_link(link),
        )
        self.text_widget.tag_bind(tag_name, "<Enter>", lambda _event: self.text_widget.configure(cursor="hand2"))
        self.text_widget.tag_bind(tag_name, "<Leave>", lambda _event: self.text_widget.configure(cursor="xterm"))

    def _open_link(self, target: str) -> None:
        clean_target = target.strip()
        if not clean_target or clean_target.startswith("#"):
            return

        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", clean_target):
            webbrowser.open(clean_target)
            return

        candidate = Path(clean_target)
        if not candidate.is_absolute() and self.base_dir is not None:
            candidate = (self.base_dir / clean_target).resolve()

        if candidate.exists():
            os.startfile(candidate)
            return

        webbrowser.open(clean_target)

    def _insert_newline(self) -> None:
        self.text_widget.insert("end", "\n")

    def _looks_like_table(self, lines: list[str], index: int) -> bool:
        if index + 1 >= len(lines):
            return False
        line = lines[index].strip()
        next_line = lines[index + 1].strip()
        return "|" in line and self._is_table_separator(next_line)

    def _is_table_separator(self, line: str) -> bool:
        trimmed = line.strip().replace("|", "")
        if not trimmed:
            return False
        return set(trimmed) <= {":", "-", " "} and "-" in trimmed

    def _is_horizontal_rule(self, line: str) -> bool:
        compact = line.replace(" ", "")
        if len(compact) < 3:
            return False
        return compact.startswith("---") or compact.startswith("***") or compact.startswith("___")


class HTMLTextRenderer(HTMLParser):
    BLOCK_TAGS = {
        "p",
        "div",
        "ul",
        "ol",
        "li",
        "blockquote",
        "pre",
        "table",
        "thead",
        "tbody",
        "tr",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
    }

    def __init__(self, renderer: MarkdownRenderer) -> None:
        super().__init__(convert_charrefs=True)
        self.renderer = renderer
        self.text_widget = renderer.text_widget
        self.inline_stack: list[tuple[str, ...]] = []
        self.list_stack: list[dict[str, int | str]] = []
        self.href_stack: list[str] = []
        self.blockquote_depth = 0
        self.in_pre = False
        self.in_table = False
        self.current_table_row: list[str] = []
        self.current_table_is_header = False
        self.table_rows: list[tuple[list[str], bool]] = []
        self.pending_newlines = 0
        self.last_text_was_space = True
        self.current_heading_level: int | None = None
        self.current_heading_title: list[str] = []
        self.current_heading_index = "1.0"

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)

        if tag == "br":
            self._flush_newlines()
            self.text_widget.insert("end", "\n")
            self.last_text_was_space = True
            return

        if tag == "hr":
            self._ensure_block_break(1)
            self._flush_newlines()
            self.text_widget.insert("end", "─" * 72 + "\n", ("hr",))
            self._ensure_block_break(1)
            return

        if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            self._ensure_block_break(1)
            level = int(tag[1])
            self._flush_newlines()
            self.current_heading_level = level
            self.current_heading_title = []
            self.current_heading_index = self.text_widget.index("end-1c")
            self.inline_stack.append((f"heading_{level}", "title"))
            return

        if tag == "p":
            self._ensure_block_break(1)
            self.inline_stack.append(("paragraph",))
            return

        if tag == "blockquote":
            self._ensure_block_break(1)
            self.blockquote_depth += 1
            self.inline_stack.append(("blockquote",))
            self._flush_newlines()
            self.text_widget.insert("end", "▎ ", ("blockquote",))
            self.last_text_was_space = False
            return

        if tag == "ul":
            self._ensure_block_break(1)
            self.list_stack.append({"type": "ul", "index": 0})
            return

        if tag == "ol":
            self._ensure_block_break(1)
            start = attributes.get("start")
            index = int(start) - 1 if start and start.isdigit() else 0
            self.list_stack.append({"type": "ol", "index": index})
            return

        if tag == "li":
            self._ensure_block_break(1)
            prefix = "• "
            if self.list_stack:
                current = self.list_stack[-1]
                if current["type"] == "ol":
                    current["index"] = int(current["index"]) + 1
                    prefix = f"{current['index']}. "
            self._flush_newlines()
            self.text_widget.insert("end", prefix, ("list_item",))
            self.inline_stack.append(("list_item",))
            self.last_text_was_space = False
            return

        if tag == "pre":
            self._ensure_block_break(1)
            self.in_pre = True
            self.inline_stack.append(("code_block",))
            return

        if tag == "code" and not self.in_pre:
            self.inline_stack.append(("inline_code",))
            return

        if tag in {"strong", "b"}:
            self.inline_stack.append(("strong",))
            return

        if tag in {"em", "i"}:
            self.inline_stack.append(("emphasis",))
            return

        if tag == "a":
            href = attributes.get("href") or ""
            self.href_stack.append(href)
            self.inline_stack.append(("link",))
            return

        if tag == "img":
            alt = (attributes.get("alt") or "image").strip() or "image"
            src = (attributes.get("src") or "").strip()
            self._flush_newlines()
            self.renderer._insert_link(f"[Image: {alt}]", src, self._current_tags())
            self.last_text_was_space = False
            return

        if tag == "table":
            self._ensure_block_break(1)
            self.in_table = True
            self.table_rows = []
            return

        if tag == "tr":
            self.current_table_row = []
            self.current_table_is_header = False
            return

        if tag == "th":
            self.current_table_is_header = True
            self.inline_stack.append(("table", "strong"))
            return

        if tag == "td":
            self.inline_stack.append(("table",))
            return

    def handle_endtag(self, tag: str) -> None:
        if tag in {"h1", "h2", "h3", "h4", "h5", "h6", "p"}:
            if tag.startswith("h") and self.current_heading_level is not None:
                heading_title = "".join(self.current_heading_title).strip()
                if heading_title:
                    self.renderer.headings.append(
                        HeadingEntry(
                            level=self.current_heading_level,
                            title=heading_title,
                            text_index=self.current_heading_index,
                        )
                    )
                self.current_heading_level = None
                self.current_heading_title = []
            self._pop_inline()
            self._ensure_block_break(1)
            return

        if tag == "blockquote":
            self._pop_inline()
            self.blockquote_depth = max(0, self.blockquote_depth - 1)
            self._ensure_block_break(1)
            return

        if tag in {"ul", "ol"}:
            if self.list_stack:
                self.list_stack.pop()
            self._ensure_block_break(1)
            return

        if tag == "li":
            self._pop_inline()
            self._ensure_block_break(1)
            return

        if tag == "pre":
            self._pop_inline()
            self.in_pre = False
            self._ensure_block_break(1)
            return

        if tag == "code" and not self.in_pre:
            self._pop_inline()
            return

        if tag in {"strong", "b", "em", "i", "th", "td"}:
            self._pop_inline()
            return

        if tag == "a":
            self._pop_inline()
            if self.href_stack:
                self.href_stack.pop()
            return

        if tag == "tr":
            if self.current_table_row:
                self.table_rows.append((self.current_table_row[:], self.current_table_is_header))
            self.current_table_row = []
            return

        if tag == "table":
            self._render_table()
            self.in_table = False
            self._ensure_block_break(1)
            return

    def handle_data(self, data: str) -> None:
        if not data:
            return

        if self.in_table and self.current_table_row is not None and self.lasttag in {"th", "td"}:
            text = self._normalize_inline_whitespace(data)
            if text:
                self.current_table_row.append(text)
            return

        if self.in_pre:
            self._flush_newlines()
            self.text_widget.insert("end", data, ("code_block",))
            self.last_text_was_space = data.endswith((" ", "\n", "\t"))
            return

        text = self._normalize_inline_whitespace(data)
        if not text:
            return

        if self.blockquote_depth and self.last_text_was_space:
            self._flush_newlines()

        if self.href_stack:
            self._flush_newlines()
            self.renderer._insert_link(text, self.href_stack[-1], self._current_tags(exclude_link=True))
        else:
            self._flush_newlines()
            self.text_widget.insert("end", text, self._current_tags())

        if self.current_heading_level is not None:
            self.current_heading_title.append(text)

        self.last_text_was_space = text.endswith(" ")

    def _render_table(self) -> None:
        if not self.table_rows:
            return

        widths: list[int] = []
        for cells, _is_header in self.table_rows:
            for index, cell in enumerate(cells):
                if index >= len(widths):
                    widths.append(0)
                widths[index] = max(widths[index], len(cell))

        for row_index, (cells, is_header) in enumerate(self.table_rows):
            padded = []
            for index, width in enumerate(widths):
                value = cells[index] if index < len(cells) else ""
                padded.append(value.ljust(width))
            rendered = " | ".join(padded)
            self._flush_newlines()
            tags = ("table", "strong") if is_header else ("table",)
            self.text_widget.insert("end", rendered + "\n", tags)
            if row_index == 0:
                separator = "-+-".join("-" * width for width in widths)
                self.text_widget.insert("end", separator + "\n", ("table",))
        self.table_rows = []
        self.last_text_was_space = True

    def _normalize_inline_whitespace(self, text: str) -> str:
        collapsed = re.sub(r"\s+", " ", text)
        if not collapsed.strip():
            return " " if not self.last_text_was_space and not self.in_pre else ""
        if self.last_text_was_space:
            collapsed = collapsed.lstrip()
        return collapsed

    def _current_tags(self, exclude_link: bool = False) -> tuple[str, ...]:
        tags: list[str] = []
        for group in self.inline_stack:
            for tag in group:
                if exclude_link and tag == "link":
                    continue
                if tag not in tags:
                    tags.append(tag)
        return tuple(tags)

    def _pop_inline(self) -> None:
        if self.inline_stack:
            self.inline_stack.pop()

    def _ensure_block_break(self, count: int) -> None:
        self.pending_newlines = max(self.pending_newlines, count)
        self.last_text_was_space = True

    def _flush_newlines(self) -> None:
        if self.pending_newlines <= 0:
            return
        self.text_widget.insert("end", "\n" * self.pending_newlines)
        self.pending_newlines = 0


class MarkdownReaderApp:
    def __init__(self, initial_folder: Path | None = None) -> None:
        self.root = tk.Tk()
        self.root.title(APP_NAME)
        self.root.geometry(f"{WINDOW_WIDTH}x{WINDOW_HEIGHT}")
        self.root.minsize(980, 620)
        self.root.configure(bg="#eee6d6")

        self.selected_folder: Path | None = None
        self.markdown_files: list[Path] = []
        self.current_file: Path | None = None
        self.search_var = tk.StringVar()
        self.tree_item_to_node: dict[str, FileNode] = {}
        self.outline_item_to_heading: dict[str, HeadingEntry] = {}
        self.renderer: MarkdownRenderer | None = None

        self._set_icon()
        self._build_ui()
        self._bind_shortcuts()
        self._show_placeholder()

        if initial_folder is not None:
            self.load_folder(initial_folder)

    def _set_icon(self) -> None:
        icon_path = resource_path("Assets/AppIconSource.png")
        if icon_path.exists():
            try:
                image = tk.PhotoImage(file=str(icon_path))
                self.root.iconphoto(True, image)
                self.root._icon_photo_ref = image  # type: ignore[attr-defined]
            except tk.TclError:
                pass

    def _build_ui(self) -> None:
        header = tk.Frame(self.root, bg="#eee6d6")
        header.pack(fill="x", padx=20, pady=(18, 10))

        title = tk.Label(
            header,
            text="Markdown Reader",
            font=("Segoe UI", 22, "bold"),
            bg="#eee6d6",
            fg="#1f2328",
        )
        title.grid(row=0, column=0, sticky="w")

        self.status_var = tk.StringVar(
            value="选择一个文件夹，程序会递归扫描全部 Markdown 文档。"
        )
        status = tk.Label(
            header,
            textvariable=self.status_var,
            font=("Segoe UI", 10),
            bg="#eee6d6",
            fg="#6b7280",
            anchor="w",
        )
        status.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(4, 0))

        controls = tk.Frame(header, bg="#eee6d6")
        controls.grid(row=0, column=1, rowspan=2, sticky="e")

        search_entry = tk.Entry(
            controls,
            textvariable=self.search_var,
            width=32,
            font=("Segoe UI", 10),
            relief="flat",
            highlightthickness=1,
            highlightbackground="#ded6c8",
            highlightcolor="#9a3412",
            bg="#fffdf8",
            fg="#1f2328",
            insertbackground="#1f2328",
        )
        search_entry.pack(side="left", padx=(0, 12), ipady=6)

        open_button = tk.Button(
            controls,
            text="Open Folder",
            command=self.choose_folder,
            bg="#9a3412",
            fg="white",
            activebackground="#c2410c",
            activeforeground="white",
            relief="flat",
            padx=18,
            pady=8,
            font=("Segoe UI", 10, "bold"),
            cursor="hand2",
        )
        open_button.pack(side="left")

        header.columnconfigure(0, weight=1)

        body = tk.PanedWindow(
            self.root,
            orient="horizontal",
            sashwidth=6,
            bg="#eee6d6",
            bd=0,
            relief="flat",
        )
        body.pack(fill="both", expand=True, padx=20, pady=(0, 20))

        sidebar = tk.Frame(body, bg="#fffdf8", highlightbackground="#ded6c8", highlightthickness=1)
        preview = tk.Frame(body, bg="#fffdf8", highlightbackground="#ded6c8", highlightthickness=1)
        body.add(sidebar, minsize=260, width=SIDEBAR_WIDTH)
        body.add(preview, minsize=360)

        tree_style = ttk.Style()
        tree_style.theme_use("clam")
        tree_style.configure(
            "Markdown.Treeview",
            background="#fffdf8",
            fieldbackground="#fffdf8",
            foreground="#1f2328",
            borderwidth=0,
            rowheight=28,
            font=("Segoe UI", 10),
        )
        tree_style.map(
            "Markdown.Treeview",
            background=[("selected", "#f4d7bf")],
            foreground=[("selected", "#1f2328")],
        )

        sidebar_scroll = ttk.Scrollbar(sidebar, orient="vertical")
        sidebar_scroll.pack(side="right", fill="y")

        self.tree = ttk.Treeview(
            sidebar,
            show="tree",
            style="Markdown.Treeview",
            yscrollcommand=sidebar_scroll.set,
            selectmode="browse",
        )
        self.tree.pack(fill="both", expand=True)
        sidebar_scroll.config(command=self.tree.yview)

        preview_split = tk.PanedWindow(
            preview,
            orient="horizontal",
            sashwidth=4,
            bg="#fffdf8",
            bd=0,
            relief="flat",
        )
        preview_split.pack(fill="both", expand=True)

        preview_text_container = tk.Frame(
            preview_split, bg="#fffdf8", highlightbackground="#ded6c8", highlightthickness=0
        )
        outline_container = tk.Frame(
            preview_split, bg="#fbf7ef", highlightbackground="#ded6c8", highlightthickness=0
        )
        preview_split.add(preview_text_container, minsize=340)
        preview_split.add(outline_container, minsize=180, width=220)

        preview_scroll = ttk.Scrollbar(preview_text_container, orient="vertical")
        preview_scroll.pack(side="right", fill="y")

        self.preview_text = tk.Text(
            preview_text_container,
            relief="flat",
            borderwidth=0,
            yscrollcommand=preview_scroll.set,
            undo=False,
        )
        self.preview_text.pack(fill="both", expand=True)
        preview_scroll.config(command=self.preview_text.yview)
        self.renderer = MarkdownRenderer(self.preview_text)
        self._build_preview_menu()

        outline_title = tk.Label(
            outline_container,
            text="Outline",
            font=("Segoe UI", 10, "bold"),
            bg="#fbf7ef",
            fg="#6b7280",
            anchor="w",
            padx=10,
            pady=10,
        )
        outline_title.pack(fill="x")

        outline_scroll = ttk.Scrollbar(outline_container, orient="vertical")
        outline_scroll.pack(side="right", fill="y")

        self.outline_tree = ttk.Treeview(
            outline_container,
            show="tree",
            style="Markdown.Treeview",
            yscrollcommand=outline_scroll.set,
            selectmode="browse",
        )
        self.outline_tree.pack(fill="both", expand=True, padx=(0, 4), pady=(0, 8))
        outline_scroll.config(command=self.outline_tree.yview)

        self.search_var.trace_add("write", lambda *_args: self.refresh_tree())
        self.tree.bind("<<TreeviewSelect>>", self._on_tree_select)
        self.tree.bind("<Double-1>", self._on_tree_double_click)
        self.outline_tree.bind("<<TreeviewSelect>>", self._on_outline_select)
        self.preview_text.bind("<Button-1>", self._focus_preview)
        self.preview_text.bind("<Button-3>", self._show_preview_menu)
        self.preview_text.bind("<Control-MouseWheel>", self._zoom_with_mousewheel)
        self.preview_text.bind("<Control-Button-4>", self._zoom_in_shortcut)
        self.preview_text.bind("<Control-Button-5>", self._zoom_out_shortcut)

    def _bind_shortcuts(self) -> None:
        self.root.bind("<Control-o>", lambda _event: self.choose_folder())
        self.root.bind("<Control-f>", self._focus_search)
        self.root.bind("<Control-c>", self._copy_selection)
        self.root.bind("<Control-a>", self._select_all_preview)
        self.root.bind("<Control-equal>", self._zoom_in_shortcut)
        self.root.bind("<Control-plus>", self._zoom_in_shortcut)
        self.root.bind("<Control-KP_Add>", self._zoom_in_shortcut)
        self.root.bind("<Control-minus>", self._zoom_out_shortcut)
        self.root.bind("<Control-KP_Subtract>", self._zoom_out_shortcut)
        self.root.bind("<Control-0>", self._reset_zoom_shortcut)

    def _build_preview_menu(self) -> None:
        self.preview_menu = tk.Menu(self.root, tearoff=False)
        self.preview_menu.add_command(label="Copy", command=self._copy_preview_selection)
        self.preview_menu.add_command(label="Select All", command=self._select_all_preview_text)
        self.preview_menu.add_separator()
        self.preview_menu.add_command(label="Zoom In", command=self._zoom_in_preview)
        self.preview_menu.add_command(label="Zoom Out", command=self._zoom_out_preview)
        self.preview_menu.add_command(label="Reset Zoom", command=self._reset_preview_zoom)

    def _focus_search(self, _event: tk.Event) -> str:
        for child in self.root.winfo_children():
            self._focus_first_entry(child)
        return "break"

    def _focus_preview(self, _event: tk.Event) -> None:
        self.preview_text.focus_set()

    def _show_preview_menu(self, event: tk.Event) -> str:
        self.preview_text.focus_set()
        try:
            self.preview_menu.tk_popup(event.x_root, event.y_root)
        finally:
            self.preview_menu.grab_release()
        return "break"

    def _copy_selection(self, _event: tk.Event) -> str | None:
        focus_widget = self.root.focus_get()
        if focus_widget == self.preview_text:
            return self._copy_preview_selection()
        return None

    def _copy_preview_selection(self) -> str:
        try:
            selected_text = self.preview_text.get("sel.first", "sel.last")
        except tk.TclError:
            return "break"

        self.root.clipboard_clear()
        self.root.clipboard_append(selected_text)
        return "break"

    def _select_all_preview(self, _event: tk.Event) -> str | None:
        if self.root.focus_get() == self.preview_text:
            return self._select_all_preview_text()
        return None

    def _select_all_preview_text(self) -> str:
        self.preview_text.focus_set()
        self.preview_text.tag_add("sel", "1.0", "end-1c")
        self.preview_text.mark_set("insert", "1.0")
        self.preview_text.see("insert")
        return "break"

    def _zoom_in_preview(self) -> str:
        if self.renderer is not None:
            self.renderer.zoom_in()
        return "break"

    def _zoom_out_preview(self) -> str:
        if self.renderer is not None:
            self.renderer.zoom_out()
        return "break"

    def _reset_preview_zoom(self) -> str:
        if self.renderer is not None:
            self.renderer.reset_zoom()
        return "break"

    def _zoom_in_shortcut(self, _event: tk.Event) -> str | None:
        if self.root.focus_get() == self.preview_text:
            return self._zoom_in_preview()
        return None

    def _zoom_out_shortcut(self, _event: tk.Event) -> str | None:
        if self.root.focus_get() == self.preview_text:
            return self._zoom_out_preview()
        return None

    def _reset_zoom_shortcut(self, _event: tk.Event) -> str | None:
        if self.root.focus_get() == self.preview_text:
            return self._reset_preview_zoom()
        return None

    def _zoom_with_mousewheel(self, event: tk.Event) -> str:
        self.preview_text.focus_set()
        if getattr(event, "delta", 0) > 0:
            return self._zoom_in_preview()
        return self._zoom_out_preview()

    def _focus_first_entry(self, widget: tk.Misc) -> bool:
        if isinstance(widget, tk.Entry):
            widget.focus_set()
            widget.selection_range(0, "end")
            return True
        for child in widget.winfo_children():
            if self._focus_first_entry(child):
                return True
        return False

    def choose_folder(self) -> None:
        selected = filedialog.askdirectory(title="Open Folder")
        if selected:
            self.load_folder(Path(selected))

    def load_folder(self, folder: Path) -> None:
        self.selected_folder = folder
        self.markdown_files = self.scan_markdown_files(folder)
        self.current_file = None
        self.refresh_tree()

        if not self.markdown_files:
            self.root.title(APP_NAME)
            self.status_var.set(f"{folder}  (没有找到 Markdown 文件)")
            self._show_message(
                "# 没找到 Markdown 文档\n\n这个文件夹里暂时没有 `.md` 或 `.markdown` 文件。"
            )
            return

        self.status_var.set(
            f"{folder}  ({len(self.markdown_files)} 个 Markdown 文件)"
        )
        first = self._first_leaf(self._build_tree(self.filtered_files()))
        if first and first.file_path:
            self._select_file(first.file_path)

    def scan_markdown_files(self, folder: Path) -> list[Path]:
        results: list[Path] = []
        for root_dir, dirnames, filenames in os.walk(folder):
            dirnames[:] = [
                name
                for name in dirnames
                if not name.startswith(".") and not self._is_hidden(Path(root_dir) / name)
            ]
            for filename in filenames:
                path = Path(root_dir) / filename
                if self._is_hidden(path):
                    continue
                if path.suffix.lower() in SUPPORTED_EXTENSIONS:
                    results.append(path)
        return sorted(results, key=lambda path: self.relative_path(path).lower())

    def _is_hidden(self, path: Path) -> bool:
        return path.name.startswith(".")

    def relative_path(self, path: Path) -> str:
        if self.selected_folder is None:
            return path.name
        return str(PurePosixPath(path.relative_to(self.selected_folder).as_posix()))

    def filtered_files(self) -> list[Path]:
        query = self.search_var.get().strip().lower()
        if not query:
            return self.markdown_files
        return [
            path
            for path in self.markdown_files
            if query in self.relative_path(path).lower()
        ]

    def _build_tree(self, files: Iterable[Path]) -> FileNode:
        root = FileNode("Root", "", directory=True)
        directories: dict[str, FileNode] = {"": root}

        for file_path in files:
            relative = self.relative_path(file_path)
            parts = PurePosixPath(relative).parts
            parent = root
            current_path = ""

            for index, part in enumerate(parts):
                current_path = f"{current_path}/{part}".strip("/")
                last = index == len(parts) - 1

                if last:
                    parent.children.append(
                        FileNode(part, current_path, file_path=file_path, directory=False)
                    )
                    continue

                directory = directories.get(current_path)
                if directory is None:
                    directory = FileNode(part, current_path, directory=True)
                    directories[current_path] = directory
                    parent.children.append(directory)
                parent = directory

        self._sort_tree(root)
        return root

    def _sort_tree(self, node: FileNode) -> None:
        node.children.sort(key=lambda child: (0 if child.directory else 1, child.name.lower()))
        for child in node.children:
            self._sort_tree(child)

    def refresh_tree(self) -> None:
        filtered = self.filtered_files()
        tree_root = self._build_tree(filtered)
        self.tree.delete(*self.tree.get_children())
        self.tree_item_to_node.clear()
        self._insert_tree_children("", tree_root)

        if not filtered:
            self.current_file = None
            self._show_message("# 没有匹配文件\n\n换个关键字试试，或者清空搜索条件。")
            return

        if self.current_file in filtered:
            self._select_file(self.current_file, preserve_preview=True)
        else:
            first = self._first_leaf(tree_root)
            if first and first.file_path:
                self._select_file(first.file_path)

    def _insert_tree_children(self, parent_item: str, node: FileNode) -> None:
        for child in node.children:
            item = self.tree.insert(parent_item, "end", text=child.name, open=True)
            self.tree_item_to_node[item] = child
            if child.directory:
                self._insert_tree_children(item, child)

    def _populate_outline(self, headings: list[HeadingEntry]) -> None:
        self.outline_tree.delete(*self.outline_tree.get_children())
        self.outline_item_to_heading.clear()

        if not headings:
            self.outline_tree.insert("", "end", text="No headings")
            return

        parent_for_level: dict[int, str] = {0: ""}
        for heading in headings:
            parent_level = max(0, heading.level - 1)
            while parent_level > 0 and parent_level not in parent_for_level:
                parent_level -= 1
            parent = parent_for_level.get(parent_level, "")
            item = self.outline_tree.insert(parent, "end", text=heading.title, open=True)
            self.outline_item_to_heading[item] = heading
            parent_for_level[heading.level] = item
            for level in list(parent_for_level.keys()):
                if level > heading.level:
                    del parent_for_level[level]

    def _on_outline_select(self, _event: tk.Event) -> None:
        selection = self.outline_tree.selection()
        if not selection:
            return
        heading = self.outline_item_to_heading.get(selection[0])
        if heading is None:
            return
        self._jump_to_heading(heading)

    def _jump_to_heading(self, heading: HeadingEntry) -> None:
        self.preview_text.focus_set()
        self.preview_text.mark_set("insert", heading.text_index)
        self.preview_text.see(heading.text_index)
        self.preview_text.tag_remove("sel", "1.0", "end")
        line_end = self.preview_text.index(f"{heading.text_index} lineend")
        self.preview_text.tag_add("sel", heading.text_index, line_end)

    def _first_leaf(self, node: FileNode) -> FileNode | None:
        for child in node.children:
            if child.directory:
                match = self._first_leaf(child)
                if match is not None:
                    return match
            else:
                return child
        return None

    def _select_file(self, file_path: Path, preserve_preview: bool = False) -> None:
        item_to_select = None
        for item_id, node in self.tree_item_to_node.items():
            if node.file_path == file_path:
                item_to_select = item_id
                break

        if item_to_select is not None:
            self.tree.selection_set(item_to_select)
            self.tree.see(item_to_select)

        if not preserve_preview or self.current_file != file_path:
            self.show_markdown(file_path)

    def _on_tree_select(self, _event: tk.Event) -> None:
        selection = self.tree.selection()
        if not selection:
            return
        node = self.tree_item_to_node.get(selection[0])
        if node and node.file_path:
            self.show_markdown(node.file_path)

    def _on_tree_double_click(self, _event: tk.Event) -> None:
        item = self.tree.focus()
        node = self.tree_item_to_node.get(item)
        if node and node.directory:
            if self.tree.item(item, "open"):
                self.tree.item(item, open=False)
            else:
                self.tree.item(item, open=True)

    def show_markdown(self, file_path: Path) -> None:
        self.current_file = file_path
        markdown_text, used_encoding = self._read_text(file_path)

        if markdown_text is None:
            self.root.title(APP_NAME)
            self._show_message(
                f"# 打开失败\n\n无法读取文件：`{file_path.name}`\n\n请确认它是 UTF-8、UTF-8 with BOM、GBK 或 GB18030 编码。"
            )
            return

        title = self.relative_path(file_path)
        self.root.title(f"{APP_NAME} - {title}")
        self.status_var.set(
            f"{self.selected_folder}  ({len(self.markdown_files)} 个 Markdown 文件，当前编码：{used_encoding})"
        )
        assert self.renderer is not None
        self.renderer.render(markdown_text, title=title, base_dir=file_path.parent)
        self._populate_outline(self.renderer.headings)
        self.preview_text.yview_moveto(0)

    def _read_text(self, file_path: Path) -> tuple[str | None, str]:
        preferred = locale.getpreferredencoding(False)
        for encoding in ("utf-8", "utf-8-sig", preferred, "gb18030", "gbk"):
            try:
                return file_path.read_text(encoding=encoding), encoding
            except UnicodeDecodeError:
                continue
            except OSError:
                break
        return None, "unknown"

    def _show_placeholder(self) -> None:
        self._show_message(
            "# 打开一个文件夹\n\n选择一个包含 Markdown 文档的文件夹，左侧会自动构建目录树，右侧显示格式化预览。\n\n- 自动递归扫描子文件夹\n- 支持按文件名和相对路径搜索\n- 支持标题、列表、任务列表、代码块、表格、链接\n- 支持 `Ctrl+O` 打开文件夹，`Ctrl+F` 聚焦搜索"
        )

    def _show_message(self, markdown_text: str) -> None:
        self.current_file = None
        assert self.renderer is not None
        self.renderer.render(markdown_text, title=APP_NAME, base_dir=None)
        self._populate_outline(self.renderer.headings)
        self.preview_text.yview_moveto(0)

    def run(self) -> None:
        self.root.mainloop()


def run_self_test() -> int:
    sample = "# Markdown Reader\n\n- [x] task\n- item\n\n| a | b |\n| - | - |\n| 1 | 2 |\n"
    assert "task" in sample
    assert TASK_LIST_PATTERN.match("- [x] task")
    assert ORDERED_LIST_PATTERN.match("1. item")
    assert INLINE_PATTERN.search("A [link](https://example.com)")
    assert markdown_lib is not None
    html = markdown_lib.markdown(
        sample,
        extensions=[
            "markdown.extensions.extra",
            "markdown.extensions.sane_lists",
            "markdown.extensions.nl2br",
        ],
        output_format="html5",
    )
    assert "<table>" in html
    assert "<li>" in html
    root = tk.Tk()
    root.withdraw()
    try:
        text = tk.Text(root)
        renderer = MarkdownRenderer(text)
        renderer.render("# Title\n\n## Section\n\nParagraph", title="test", base_dir=None)
        assert len(renderer.headings) == 2
        assert renderer.headings[0].title == "Title"
        assert renderer.headings[1].title == "Section"
    finally:
        root.destroy()
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Markdown Reader for Windows")
    parser.add_argument("folder", nargs="?", help="Open a folder immediately")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run a quick import/parser smoke test and exit",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(list(argv or sys.argv[1:]))
    if args.self_test:
        return run_self_test()

    initial_folder = Path(args.folder).resolve() if args.folder else None
    app = MarkdownReaderApp(initial_folder=initial_folder)
    app.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
