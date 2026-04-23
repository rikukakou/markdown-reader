#!/usr/bin/env python3

from pathlib import Path
import sys

from PIL import Image


SIZES = [
    (16, 16),
    (32, 32),
    (64, 64),
    (128, 128),
    (256, 256),
    (512, 512),
    (1024, 1024),
]


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: generate_icon.py <source.png> <output.icns>", file=sys.stderr)
        return 1

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.parent.mkdir(parents=True, exist_ok=True)

    with Image.open(source) as image:
        image.convert("RGBA").save(output, sizes=SIZES)

    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
