# Tandy Color Computer 3 for the Raspberry Pi Pico series — PureMetal

A CoCo 3 emulator for the Pico W (RP2040) and Pico 2 W (RP2350), written in PureMetal and compiled
with PureMetalForge to bare-metal machine code. The CPU is the computed-goto 6809 core of
[6809EmulatorPicoSeries](../6809EmulatorPicoSeries) (clone it beside this repository); this repository
is the machine around it.

**No ROMs are included.** The CoCo 3 ROM and Disk BASIC are Tandy's; you load your own copies into
the board's flash with the tools below. The firmware image contains none of them.

## What is emulated

| Part | State |
|---|---|
| GIME MMU: 8 KB pages, two task register sets, MMU on/off, ROM modes (16K/16K, 32K internal, 32K external), the $FExx constant page, all-RAM mode (SAM TY) | written |
| GIME video: text 32/40/64/80 columns with attributes (colours, blink, underline), graphics 16-160 bytes a row in 2/4/16 colours, 192/200/225 lines, the palette, border, vertical scroll, horizontal offset and virtual width | written, diagnostic on the board pending |
| VDG-compatible modes (CoCo 1/2 software): 32 x 16 text with MC6847T1 lower case, semigraphics 4, the CG and RG graphics modes, SAM display offset | written |
| GIME interrupts: timer (63.5 us and 279 ns inputs), HBORD, VBORD, keyboard (EI1); IRQ and FIRQ routing; PIA0 HSYNC/VSYNC interrupts; PIA1 FIRQ | written |
| PIA0: keyboard matrix (with ALT, CTRL, F1, F2), joystick comparator and mux; PIA1: 6-bit DAC, single-bit sound, SNDEN, RAM size sense | written |
| 0.89 / 1.79 MHz ($FFD8/$FFD9), paced to the real machine's 59.94 frames a second | written |
| FD-502 disk controller: DSKREG and a WD1793, four .DSK drives in flash, writes kept | written |
| Sound to a Bluetooth speaker | sampling written (48 kHz ring); speaker output not yet |
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
| Pico W | below $50000 | $140000-$14FFFF | $150000-$1F3FFF (4 x $29000) |
| Pico 2 W | below $50000 | $3E0000-$3EFFFF | $300000-$3A3FFF |

These stay clear of the NES ROM store, the radio firmware and the Bluetooth link key that other
programs keep on the same boards.

## Use

```powershell
py -3 tools/make_rom_region.py --rom <your coco3.rom> --cart <your disk11.rom> --out private/coco_rom.uf2
& <PureMetalForge.exe> --radio-firmware private/coco_rom.uf2 --port COM7
tools/build.ps1 -Compiler <PureMetalForge.exe> -Port COM7
py -3 tools/console.py --port COM7
```

`tools/build.ps1` builds, checks where the image ends, uploads through PureMetalForge's own upload,
and can run a `tools/board.py` script against the board (type keys, wait for text on the CoCo screen,
capture the rendered picture as a PNG). Ctrl+] then a letter is a monitor command: `s` status, `t` the
text on the screen, `c` capture, `f` full speed, `p` CPU registers, `r` reset.

## Measured

Nothing is claimed until it has run on a board; results go here with the commands that produced them.

## Sources

MAME's `gime.cpp`, `coco3.cpp`, `coco.cpp`, `coco_fdc.cpp` and `mc6847.cpp` (BSD-3-Clause) were read
for the hardware's behaviour; the 64 composite colours are MAME's table (`src/video.pmi`). No MAME code
is compiled into the firmware.
