from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "entry/src/main/resources/base/media/launcher_icon_foreground.png"
OUTPUT = ROOT / "docs/release-assets/app-icon-1024.png"


def extend_transparent_edges(source: Image.Image) -> Image.Image:
    rgba = np.asarray(source.convert("RGBA"), dtype=np.uint8)
    rgb = rgba[:, :, :3].copy()
    alpha = rgba[:, :, 3]
    filled = alpha == 255
    height, width = alpha.shape
    queue: deque[tuple[int, int]] = deque()

    for y in range(height):
        for x in range(width):
            if not filled[y, x]:
                continue
            if ((y > 0 and not filled[y - 1, x]) or
                    (y + 1 < height and not filled[y + 1, x]) or
                    (x > 0 and not filled[y, x - 1]) or
                    (x + 1 < width and not filled[y, x + 1])):
                queue.append((y, x))

    directions = ((-1, 0), (1, 0), (0, -1), (0, 1),
                  (-1, -1), (-1, 1), (1, -1), (1, 1))
    while queue:
        y, x = queue.popleft()
        for dy, dx in directions:
            ny = y + dy
            nx = x + dx
            if ny < 0 or ny >= height or nx < 0 or nx >= width or filled[ny, nx]:
                continue
            rgb[ny, nx] = rgb[y, x]
            filled[ny, nx] = True
            queue.append((ny, nx))

    opacity = alpha.astype(np.float32)[:, :, None] / 255.0
    original = rgba[:, :, :3].astype(np.float32)
    extended = rgb.astype(np.float32)
    flattened = np.rint(original * opacity + extended * (1.0 - opacity)).astype(np.uint8)
    return Image.fromarray(flattened, mode="RGB")


def main() -> None:
    with Image.open(SOURCE) as source:
        if source.size != (1024, 1024):
            raise ValueError(f"Expected a 1024x1024 source icon, got {source.size}")
        result = extend_transparent_edges(source)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    result.save(OUTPUT, format="PNG", optimize=True, compress_level=9)
    if OUTPUT.stat().st_size > 3 * 1024 * 1024:
        raise ValueError("Generated icon exceeds the 3 MB AppGallery limit")


if __name__ == "__main__":
    main()
