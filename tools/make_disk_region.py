"""Put .DSK (JVC) disk images into the firmware's four disk slots, as a UF2 the compiler can send.

    py -3 tools/make_disk_region.py --drive 0 games.dsk --drive 1 blank --out private/disks.uf2
    PureMetalForge.exe --radio-firmware private/disks.uf2 --port COM7

`blank` is an empty disk Disk BASIC can use at once: 35 tracks, single sided, its directory track (17)
initialised as DSKINI leaves it (granule table $FF, directory entries $FF). A slot not named is left as
it is on the board (its sectors are not in the UF2). Only the named slots are written, whole.

Slot layout (src/disk.pmi reads it): +$0000 "CDSK", version 2, image bytes, tracks, sides, sectors per
track (18), JVC header length; +$100 the image as the file holds it (its JVC header included).
A slot is $28000 bytes: a 35-track single-sided disk (161,280 bytes) fits; a larger image is refused.
The four slots run $150000-$1EFFFF on a Pico W, below the C64 emulator's region at $1F0000.
"""
import argparse
import struct
import sys
from pathlib import Path

FAMILY = {'rp2040': 0xE48BFF56, 'rp2350': 0xE48BFF59}
OFFSET = {'rp2040': 0x150000, 'rp2350': 0x300000}
SLOT = 0x28000
DATA = 0x100


def uf2_blocks(data, base, family):
    out = []
    for n in range(0, len(data), 256):
        out.append((base + n, data[n:n + 256].ljust(256, b'\xff')))
    return out


def blank_disk():
    img = bytearray(b'\xff' * (35 * 18 * 256))
    # track 17: sector 2 the granule table (68 granules free = $FF), sectors 3-11 the directory ($FF
    # in the first byte of an entry is never used; DSKINI writes the whole sectors $FF), the rest $FF.
    return bytes(img)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--drive', nargs=2, action='append', metavar=('N', 'FILE'), required=True,
                   help='drive number 0-3 and a .DSK file, or the word blank')
    p.add_argument('--target', choices=sorted(FAMILY), default='rp2040')
    p.add_argument('--offset', type=lambda s: int(s, 0), help='flash offset of slot 0 (default per target)')
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    base = 0x10000000 + (a.offset if a.offset is not None else OFFSET[a.target])
    blocks = []
    for n, name in a.drive:
        n = int(n)
        if not 0 <= n <= 3:
            sys.exit(f'Drive {n}: the slots are 0-3. Nothing was written.')
        data = blank_disk() if name == 'blank' else Path(name).read_bytes()
        head = len(data) % 256
        body = len(data) - head
        sides = 1
        if head >= 2 and data[1] == 2:
            sides = 2
        if body % (18 * 256 * sides):
            sys.exit(f'{name}: {body} bytes of sectors is not a whole number of 18-sector tracks. Nothing was written.')
        tracks = body // (18 * 256 * sides)
        if not 1 <= tracks <= 80:
            sys.exit(f'{name}: {tracks} tracks; 1-80 are supported. Nothing was written.')
        if DATA + len(data) > SLOT:
            sys.exit(f'{name}: {len(data)} bytes does not fit a slot of {SLOT - DATA}. Nothing was written.')
        slot = bytearray(b'\xff' * SLOT)
        slot[0:28] = b'CDSK' + struct.pack('<6I', 2, len(data), tracks, sides, 18, head)
        slot[DATA:DATA + len(data)] = data
        blocks += uf2_blocks(bytes(slot), base + n * SLOT, FAMILY[a.target])
        print(f'drive {n}: {name}, {tracks} tracks, {sides} side(s), flash ${base - 0x10000000 + n * SLOT:06X}')
    out = bytearray()
    for i, (addr, chunk) in enumerate(blocks):
        out += struct.pack('<8I', 0x0A324655, 0x9E5D5157, 0x2000, addr, 256, i, len(blocks), FAMILY[a.target])
        out += chunk + bytes(476 - 256) + struct.pack('<I', 0x0AB16F30)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_bytes(out)
    print(f'{a.out}: {len(blocks)} blocks')


if __name__ == '__main__':
    main()
