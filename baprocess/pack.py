from pathlib import Path
from typing import Optional
import json
import os
import struct

from tqdm import tqdm
from PIL import Image, ImageDraw
import cv2
import numpy as np
from multiprocessing import Pool, cpu_count

INPUT = "badapple.webm"
MAX_WIDTH = 64
THRESHOLD = 255 * 0.4  # lum

BOXES_JSON = "boxes.json"
BOXES_BIN = "output/boxes.bin"

DEBUG_MODE = False
NUM_WORKERS = max(1, cpu_count() - 2) # not recommended to be too high, as it can crash

os.makedirs("output", exist_ok=True)


def threshold_frame(bgr: np.ndarray) -> np.ndarray:
    # compress and threshold bgr to be black and white mask

    h, w = bgr.shape[:2]
    new_w = MAX_WIDTH
    new_h = max(1, round(MAX_WIDTH * h / w))

    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    resized = cv2.resize(gray, (new_w, new_h), interpolation=cv2.INTER_AREA)
    return resized > THRESHOLD


def largest_rect(hist: np.ndarray) -> tuple[int, int, int]:
    # largest rectangle in histogram alg

    stack: list[tuple[int, int]] = []
    best_area = 0
    best = (0, 0, 0)
    n = len(hist)

    for col in range(n + 1):
        h = int(hist[col]) if col < n else 0
        start = col
        while stack and stack[-1][1] > h:
            s_col, s_h = stack.pop()
            area = (col - s_col) * s_h
            if area > best_area:
                best_area = area
                best = (s_col, col - s_col, s_h)
            start = s_col
        stack.append((start, h))

    return best


def pack_frame(white: np.ndarray) -> list[list[int]]:
    # build histogram, segment rectangles and save coord

    h, w = white.shape
    remaining = white.copy()
    boxes: list[list[int]] = []

    while remaining.any():
        hist = np.zeros(w, dtype=np.int32)
        best_area = 0
        best_box: Optional[list[int]] = None

        for row in range(h):
            hist = np.where(remaining[row], hist + 1, 0)
            col, rw, rh = largest_rect(hist)
            area = rw * rh
            if area > best_area:
                best_area = area
                best_box = [col, row - rh + 1, rw, rh]

        if best_box is None or best_area == 0:
            break

        x, y, rw, rh = best_box
        remaining[y : y + rh, x : x + rw] = False
        boxes.append(best_box)

    boxes.sort(key=lambda b: (b[1], b[0]))
    return boxes


def process_frame(args) -> list[list[int]]:
    # worker's
    # get bgr -> threshold -> pack

    bgr_bytes, shape = args
    bgr = np.frombuffer(bgr_bytes, dtype=np.uint8).reshape(shape)
    white = threshold_frame(bgr)
    return pack_frame(~white)


DEBUG_COLORS = (
    "red",
    "green",
    "blue",
    "orange",
    "yellow",
    "purple",
    "pink",
    "cyan",
    "gray",
    "brown",
    "maroon",
    "hotpink",
    "gold",
    "chocolate",
)


def debug_frame(boxes: list[list[int]], w: int, h: int, name: str) -> None:
    # draw boxes for the frame to visualize

    SCALE = 8

    img = Image.new("RGB", (w * SCALE, h * SCALE), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    colors = list(DEBUG_COLORS)
    for i, (bx, by, bw, bh) in enumerate(boxes):
        draw.rectangle(
            [(bx * SCALE, by * SCALE), ((bx + bw) * SCALE - 1, (by + bh) * SCALE - 1)],
            fill=colors[i % len(colors)],
        )
    img.save(f"{name}.png")


def load_existing(path: str) -> Optional[list]:
    if not Path(path).exists():
        return None
    with open(path) as f:
        return json.load(f)


def write_bin(frames: list[list[list[int]]], path: str) -> None:
    # pack boxes into a binary
    # [x, y, w, h] rectangles data
    # [0, 0, 0, 0] end of frame

    total_records = sum(len(f) + 1 for f in frames)
    buf = bytearray(total_records * 4)
    offset = 0
    pack_into = struct.pack_into

    for frame in frames:
        for box in frame:
            pack_into("4B", buf, offset, *box)
            offset += 4
        offset += 4 # zeros

    with open(path, "wb") as f:
        f.write(buf)


def print_stats(frames: list) -> None:
    print(f"total frames : {len(frames)}")
    print(f"most boxes   : {max(len(f) for f in frames)}")
    print(f"total boxes  : {sum(len(f) for f in frames)}")

    max_x = max((c[0] + c[2] for f in frames for c in f), default=0)
    max_y = max((c[1] + c[3] for f in frames for c in f), default=0)
    print(f"grid size    : {max_x}x{max_y}")


def process_video(path: str) -> list:
    capture = cv2.VideoCapture(path)

    print("reading video frames...")
    raw_frames: list[tuple[bytes, tuple]] = []
    while capture.isOpened():
        ret, bgr = capture.read()
        if not ret:
            break
        raw_frames.append((bgr.tobytes(), bgr.shape))
    capture.release()

    print(f"read {len(raw_frames)} frames, processing with {NUM_WORKERS} workers...")
    all_boxes: list[list[list[int]]] = []
    with Pool(NUM_WORKERS) as pool:
        for boxes in tqdm(
            pool.imap(process_frame, raw_frames, chunksize=16),
            total=len(raw_frames),
        ):
            all_boxes.append(boxes)

    return all_boxes


def main() -> None:
    existing = load_existing(BOXES_JSON)
    if existing is not None:
        print("skipping video decode...")
        frames = existing
    else:
        frames = process_video(INPUT)
        with open(BOXES_JSON, "w") as f:
            json.dump(frames, f)
        print(f"saved {BOXES_JSON}")

    print_stats(frames)
    write_bin(frames, BOXES_BIN)
    print(f"wrote {BOXES_BIN}")


if __name__ == "__main__":
    main()
