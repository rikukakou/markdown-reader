#!/usr/bin/env python3

from pathlib import Path
import sys


def load_pillow() -> object:
    repo_root = Path(__file__).resolve().parent.parent
    local_deps = repo_root / ".tools" / "python-deps"
    if local_deps.exists():
        sys.path.insert(0, str(local_deps))

    from PIL import Image

    return Image


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: generate_windows_icon.py <source.png> <output.ico>", file=sys.stderr)
        return 1

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.parent.mkdir(parents=True, exist_ok=True)

    image_module = load_pillow()
    sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    with image_module.open(source) as image:
        image.convert("RGBA").save(output, sizes=sizes)

    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
