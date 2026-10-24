# Tandy Color Computer 3 for the Raspberry Pi Pico series — PureMetal

A CoCo 3 emulator for the Pico W (RP2040) and Pico 2 W (RP2350), written in PureMetal and compiled
with PureMetalForge to bare-metal machine code. The CPU is the computed-goto 6809 core of
[6809EmulatorPicoSeries](../6809EmulatorPicoSeries) (clone it beside this repository); this repository
is the machine around it.

**No ROMs are included.** The CoCo 3 ROM and Disk BASIC are Tandy's. `tools/build_roms.ps1` assembles
them from the disassembled sources of [tomctomc/coco_roms](https://github.com/tomctomc/coco_roms) (checked
against the SHA-1s MAME lists) and puts them in the board's flash; the firmware image contains none of them.

## What is emulated

| Part | State |
|---|---|
| GIME MMU: 8 KB pages, two task register sets, MMU on/off, ROM modes (16K/16K, 32K internal, 32K external), the $FExx constant page, all-RAM mode (SAM TY) | written |
| GIME video: text 32/40/64/80 columns with attributes (colours, blink, underline), graphics 16-160 bytes a row in 2/4/16 colours, 192/200/225 lines, the palette, border, vertical scroll, horizontal offset and virtual width | run on the board (diagnostic, every mode captured) |
| VDG-compatible modes (CoCo 1/2 software): 32 x 16 text with MC6847T1 lower case, semigraphics 4, the CG and RG graphics modes, SAM display offset | written |
| GIME interrupts: timer (63.5 us and 279 ns inputs), HBORD, VBORD, keyboard (EI1); IRQ and FIRQ routing; PIA0 HSYNC/VSYNC interrupts; PIA1 FIRQ | written |
| PIA0: keyboard matrix (with ALT, CTRL, F1, F2), joystick comparator and mux; PIA1: 6-bit DAC, single-bit sound, SNDEN, RAM size sense | written |
| 0.89 / 1.79 MHz ($FFD8/$FFD9), paced to the real machine's 59.92 frames a second (262 lines of 1824 GIME clocks) | run on the board (both speeds measured) |
| FD-502 disk controller: DSKREG and a WD1793, four .DSK drives in flash, writes kept | run on the board: DIR, SAVE, LOAD |
| Sound to a Bluetooth speaker | written: 48 kHz DAC sampling and the speaker path (private build, it compiles); not yet heard on the board |
| Cassette, RS-232, cartridge autostart, joystick hardware | not emulated |

Guest RAM is **128 KB** on both boards. 512 KB does not fit: on the Pico W the 6809 core's code takes
about 85 KB of the 264 KB SRAM (it runs from SRAM for speed); on the Pico 2 W 128 KB leaves 287 KB,
less than the 384 KB more a 512 KB machine needs. A PSRAM board (Pimoroni Pico Plus 2 W) is where a
512 KB CoCo 3 would go.

## Hardware

The LAFVIN ST7796 kit, wired as the NES emulator in this family uses it: SCK GP2, MOSI GP3 (SPI0,
100 MHz on the Pico W), CS GP5, DC GP6, RESET GP7. The 640 x 240 CoCo picture (borders included) is
shown on the 480 x 320 panel at 3:4 horizontally and 4:3 vertically; a line is sent only when it changed.

The keyboard is the PC's, over the board's USB serial port: `py -3 tools/console.py --port COM7`.

## Flash layout

| Board | Program | ROMs (`make_rom_region.py`) | Disks (`make_disk_region.py`) |
|---|---|---|---|
| Pico W | below $50000 | $140000-$14FFFF | $150000-$1EFFFF (4 x $28000) |
| Pico 2 W | below $50000 | $3E0000-$3EFFFF | $300000-$39FFFF (overlaps a PDP-11 RK0 pack at $240000-$3FFFFF: not both) |

On the Pico W these stay clear of the NES ROM store, the radio firmware, the C64 emulator's region ($1F0000)
and the Bluetooth link key that other
programs keep on the same boards.

## Use

```powershell
tools/build_roms.ps1 -Source <clone of coco_roms> -Out private/coco_rom.uf2
& <PureMetalForge.exe> --radio-firmware private/coco_rom.uf2 --port COM7
py -3 tools/make_disk_region.py --drive 0 blank --out private/disks.uf2
& <PureMetalForge.exe> --radio-firmware private/disks.uf2 --port COM7
tools/build.ps1 -Compiler <PureMetalForge.exe> -Port COM7
py -3 tools/console.py --port COM7
```

`tools/build.ps1` builds, checks where the image ends, uploads through PureMetalForge's own upload,
and can run a `tools/board.py` script against the board (type keys, wait for text on the CoCo screen,
capture the rendered picture as a PNG). Ctrl+] then a letter is a monitor command: `s` status, `t` the
text on the screen, `c` capture, `f` full speed, `p` CPU registers, `r` reset.

## Measured

Pico W (RP2040 at 200 MHz), the LAFVIN panel attached, 2026-10-23. Every figure is the firmware's own
status line read over USB by `tools/board.py`; the scripts are in `tests/`.

- **Boots Disk Extended Color BASIC 2.1** to `OK` and runs a typed program (`tests/basic_boot.txt`:
  `PRINT 2+3`, then `10 FOR I=1 TO 5 / 20 PRINT I*I / 30 NEXT I / RUN` prints 1 4 9 16 25).
- **Speed against a real CoCo 3** (`tests/speed.txt`, BASIC running `10 A=A+1:GOTO 10`):

  | | real CoCo 3 | here, paced | here, unthrottled (monitor `f`) |
  |---|---:|---:|---:|
  | 0.89 MHz | 894.9 kHz, 59.92 frames/s | 894 kHz, 59.92 frames/s, core 0 29% busy | **3,064 kHz, 205 frames/s = 3.43x** |
  | 1.79 MHz (`POKE 65497,0`) | 1,789.8 kHz | 1,790 kHz, core 0 44% busy | **4,034 kHz, 135 frames/s = 2.25x** |

  Paced is the default: the machine runs at exactly the real machine's rate. The unthrottled rate at
  0.89 MHz is lower in kHz because the machine's per-scanline work is the same at both speeds.
- Disk: `DIR`, `SAVE "PICO"`, `LOAD "PICO"` on a blank disk in flash (`tests/disk.txt`).

## Sources

MAME's `gime.cpp`, `coco3.cpp`, `coco.cpp`, `coco_fdc.cpp` and `mc6847.cpp` (BSD-3-Clause) were read
for the hardware's behaviour; the 64 composite colours are MAME's table (`src/video.pmi`). No MAME code
is compiled into the firmware.
