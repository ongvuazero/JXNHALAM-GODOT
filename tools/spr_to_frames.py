"""Extract a local SPR file to RGBA PNGs, retaining original canvas alignment.
Usage: py -m pip install pillow
       py tools/spr_to_frames.py path/to/file.spr --output extracted
The extractor is designed for the 32-byte indexed JX-style SPR\0 variant.
Rights to the input images remain with their original owners.
"""
import argparse
import json
import struct
from pathlib import Path
from PIL import Image


def unpack_file(path: Path):
    data = path.read_bytes()
    if len(data) < 40 or data[:4] != b"SPR\x00":
        raise ValueError("Not a supported SPR\\0 file")
    w, h, cx, cy, frames, colors, directions, interval = struct.unpack_from('<HHhhHHHH', data, 4)
    if not (0 < colors <= 256 and 0 < frames <= 2048 and 0 < directions <= 32):
        raise ValueError("Unsupported SPR header")
    palette = [tuple(data[32 + 3 * i:35 + 3 * i]) for i in range(colors)]
    table = 32 + colors * 3
    payload = table + frames * 8
    if payload > len(data):
        raise ValueError("Frame table outside file")
    meta = dict(width=w, height=h, pivot_x=cx, pivot_y=cy, total_frames=frames,
                directions=directions, frames_per_direction=frames // directions, interval=interval)
    for frame_no in range(frames):
        off, size = struct.unpack_from('<II', data, table + 8 * frame_no)
        pos = payload + off
        if pos + size > len(data):
            pos = off
        if pos + size > len(data) or size < 8:
            raise ValueError(f"Frame {frame_no}: invalid offset")
        fw, fh, ox, oy = struct.unpack_from('<HHhh', data, pos)
        if fw * fh > 4194304:
            raise ValueError(f"Frame {frame_no}: unreasonable image size")
        rgba = bytearray(fw * fh * 4)
        p, end, n = pos + 8, pos + size, 0
        while n < fw * fh and p + 1 < end:
            count, alpha = data[p], data[p + 1]
            p += 2
            if count == 0:
                continue
            if n + count > fw * fh:
                raise ValueError("Pixel overflow")
            if alpha:
                if p + count > end:
                    raise ValueError("Palette indexes truncated")
                for k in range(count):
                    idx = data[p + k]
                    if idx >= colors:
                        raise ValueError("Palette index out of bounds")
                    r, g, b = palette[idx]
                    rgba[(n + k)*4:(n+k)*4+4] = bytes((r, g, b, alpha))
                p += count
            n += count
        if n != fw * fh:
            raise ValueError(f"Frame {frame_no}: incomplete pixels ({n}/{fw*fh})")
        tile = Image.frombytes('RGBA', (fw, fh), bytes(rgba))
        canvas = Image.new('RGBA', (w, h))
        canvas.alpha_composite(tile, (ox, oy))
        yield frame_no, canvas, meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('spr', type=Path)
    ap.add_argument('--output', '-o', type=Path, default=Path('out_spr'))
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result = None
    for index, img, meta in unpack_file(args.spr):
        img.save(args.output / f'frame_{index:04d}.png')
        result = meta
    if result:
        (args.output/'animation.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(f'Extracted {result["total_frames"]} frames in {args.output}')


if __name__ == '__main__':
    main()
