"""Pack your own CoCo 3 ROM (and optionally a Disk BASIC ROM) into the firmware's ROM region, as a UF2.

    py -3 tools/make_rom_region.py --rom coco3.rom [--cart disk11.rom] --out private/coco_rom.uf2

Send the result with the compiler's own upload (the program on the board stays):

    PureMetalForge.exe --radio-firmware private/coco_rom.uf2 --port COM7

The ROMs are commercial: keep them, and the .uf2 made from them, out of git (private/ is ignored).

Region layout (src/coco3.pmi reads it): +$0000 "CC3R", version 1, ROM bytes, ROM CRC-32, cartridge bytes,
cartridge CRC-32, font offset; +$1000 the 32 KB ROM; +$9000 the cartridge (8 or 16 KB).

THE FONT. The GIME's character generator is inside the chip, so the firmware draws text with the 8 x 8
HPRINT glyphs of Super Extended Color BASIC, ASCII 32-127, from your ROM. They start at $F09D (ROM offset
$709D) in the CoCo 3 ROM; the tool checks that the table there looks like a font (a blank space, then
glyphs with ink), prints three of them, and refuses otherwise - pass --font-offset for another ROM.
"""
import argparse
import struct
import sys
import zlib
from pathlib import Path

FAMILY = {'rp2040': 0xE48BFF56, 'rp2350': 0xE48BFF59}


def glyph_art(rom, off, ch):
    rows = rom[off + (ch - 32) * 8: off + (ch - 32) * 8 + 8]
    return [''.join('#' if (b >> (7 - i)) & 1 else '.' for i in range(8)) for b in rows]


def font_plausible(rom, off):
    if off < 0 or off + 768 > len(rom):
        return False
    if any(rom[off:off + 8]):                       # space must be blank
        return False
    inked = sum(1 for c in range(33, 127) if any(rom[off + (c - 32) * 8: off + (c - 32) * 8 + 8]))
    return inked >= 90


def uf2(data, base, family):
    blocks = [data[i:i + 256] for i in range(0, len(data), 256)]
    out = bytearray()
    for n, chunk in enumerate(blocks):
        chunk = chunk.ljust(256, b'\xff')
        head = struct.pack('<8I', 0x0A324655, 0x9E5D5157, 0x2000, base + n * 256, 256, n, len(blocks), family)
        out += head + chunk + bytes(476 - 256) + struct.pack('<I', 0x0AB16F30)
    return bytes(out)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--rom', type=Path, required=True, help='the 32 KB CoCo 3 ROM (coco3.rom)')
    p.add_argument('--cart', type=Path, help='a cartridge ROM for $C000, e.g. Disk BASIC 1.1 (8 KB)')
    p.add_argument('--font-offset', type=lambda s: int(s, 0), default=0x709D)
    p.add_argument('--offset', type=lambda s: int(s, 0), default=0x140000, help='flash offset of the region')
    p.add_argument('--target', choices=sorted(FAMILY), default='rp2040')
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--bin', type=Path, help='also write the raw region (for checking)')
    a = p.parse_args()

    rom = a.rom.read_bytes()
    if len(rom) != 32768:
        sys.exit(f'{a.rom} is {len(rom)} bytes; a CoCo 3 ROM is 32768. Nothing was written.')
    cart = a.cart.read_bytes() if a.cart else b''
    if cart and len(cart) not in (8192, 16384):
        sys.exit(f'{a.cart} is {len(cart)} bytes; a cartridge ROM here must be 8192 or 16384. Nothing was written.')
    if rom[0x7FFE:0x8000] == b'\xff\xff' or rom[0x7FFE] < 0x80:
        sys.exit(f'{a.rom}: the reset vector at $FFFE is {rom[0x7FFE]:02X}{rom[0x7FFF]:02X}, not into the ROM. '
                 'Is this a CoCo 3 ROM? Nothing was written.')
    if not font_plausible(rom, a.font_offset):
        sys.exit(f'No HPRINT font table at ROM offset ${a.font_offset:04X} (space not blank, or too few glyphs). '
                 'Pass --font-offset for this ROM. Nothing was written.')
    for ch in (ord('A'), ord('g'), ord('0')):
        print(f"glyph '{chr(ch)}':  " + ' '.join(glyph_art(rom, a.font_offset, ch)))

    region = bytearray(b'\xff' * 0x10000)
    head = b'CC3R' + struct.pack('<6I', 1, len(rom), zlib.crc32(rom), len(cart), zlib.crc32(cart) if cart else 0,
                                 a.font_offset)
    region[0:len(head)] = head
    region[0x1000:0x1000 + len(rom)] = rom
    if cart:
        region[0x9000:0x9000 + len(cart)] = cart
    used = 0x9000 + len(cart) if cart else 0x9000
    used = (used + 4095) // 4096 * 4096
    data = bytes(region[:used])
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_bytes(uf2(data, 0x10000000 + a.offset, FAMILY[a.target]))
    if a.bin:
        a.bin.write_bytes(data)
    print(f'{a.out}: {len(data)} bytes at flash ${a.offset:06X}-${a.offset + len(data) - 1:06X}, '
          f'ROM CRC-32 {zlib.crc32(rom):08X}' + (f', cartridge CRC-32 {zlib.crc32(cart):08X}' if cart else ''))


if __name__ == '__main__':
    main()
