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
| Sound to a Bluetooth speaker | partly run: the private build connected and streamed BASIC's SOUND (455 packets), then the stream stalled with the link still up; the next start found no speaker (page timeout). Open |
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
| Feather RP2350 HSTX (`coco3_feather.pico2w`) | below $40000 | $4A2000-$4BFFFF | one slot, $6B5000-$6DCFFF (of $6B5000-$6FFFFF), between the PDP-11 packs |

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
- **RP2350**: the same tests on an Adafruit Feather RP2350 HSTX (the Pico 2 W build, 150 MHz, no panel - the
  picture read over USB): BASIC boots and runs the program, the TIMER loop counts **910** as on the Pico W and the
  PC, and the demo LOADMs from its flash disk and runs; at 0.89 MHz the machine uses 23% of core 0.
- **Thumb-2 on the RP2350 (2026-10-25).** The renderer's four inner loops - the 640 -> 480 scale with its
  hash, the GIME graphics bytes, the glyph dots of every text mode, the border fill - are Cortex-M33
  assembly on the Pico 2 builds (`src/video_t2.pmi`) and PureMetal on the RP2040 and the PC
  (`src/video_portable.pmi`), both run from SRAM. Same tests, same boards, compiler `9777f6cd6`, 6809 core
  `61d7444`; core 1's figure is whole 240-line pictures rendered a second (the panel can show 60):

  | | before | after |
  |---|---:|---:|
  | **Feather RP2350**, render, BASIC text | 16.5 /s | **44.5 /s** (2.7x) |
  | **Feather RP2350**, render, the demo (320 x 192 x 16) | 11.5 /s | **59.7 /s** (5.2x) |
  | Feather RP2350, unthrottled 0.89 / 1.79 MHz | 3,420 / 4,235 kHz | 3,525 / 4,255 kHz |
  | **Pico W RP2040** (Thumb-1, must not regress), render, text | 16.4 /s | 16.5-17.6 /s |
  | Pico W RP2040, unthrottled 0.89 / 1.79 MHz | 3,130 / 4,101 kHz | **3,450 / 4,362 kHz** (+10% / +6%) |

  On the RP2040 the gain is from the kernels moving into SRAM (they had shared the flash cache with core
  0) and from a scanline's end doing less: HSYNC sets CA1's flag in one step, the body's end is a table.
  The palette is looked up again only when a palette register moves. Proof that the assembly draws what
  the PureMetal draws: `tools/vcheck_build.py` makes a build that runs both on every call, on the same
  inputs, and counts differences - through every mode BASIC reaches and the demo (`tests/vcheck.txt`):
  199,297 scale calls, 2,471,728 glyph rows, 84,942 graphics runs, 39,864 fills, **0 differences**. The
  RP2040's six mode pictures (`tests/video_modes.txt`) are byte-identical to before; BASIC, the TIMER loop
  (910) and the demo pass on both chips.

  Then the 6809 core's own Thumb-2 dispatch tail and short branches (its commit `d9f5978`; its RP2040 file
  is unchanged): Feather RP2350 unthrottled **3,525 -> 3,736 kHz (4.17x a real CoCo 3) at 0.89 MHz and
  4,255 -> 4,560 kHz (2.55x) at 1.79 MHz**, core 0 24% busy paced at 0.89 MHz, 39% at 1.79; BASIC, the
  TIMER loop (910) and the demo pass. From both: 3,420 -> 3,736 kHz and 4,235 -> 4,560 kHz on the RP2350.
- Disk: on a blank disk in flash a typed program is SAVEd, wiped, LOADed and RUN (`tests/disk.txt`); after
  a reflash and cold boot `DIR` still lists it and it LOADs and RUNs (`tests/disk_persist.txt`).

## The desktop program (desktop/)

The same CoCo 3 on a Windows PC, in PureBasic, drawn with the Neon Arcade Display Engine. It compiles the
machine files in `src/` unchanged (GIME, PIAs, video, keyboard, sound, FD-502) with the PC's own host layer
(`desktop/host.pbi`) and the desktop 6809 core of 6809EmulatorPicoSeries (`desktop/cpu6809.pbi`, clone it
beside this repository). The PC gives the CoCo **512 KB**, and the FD-502's drives are `.DSK` files.

```powershell
& "C:\Program Files\PureBasic\Compilers\pbcompilerc.exe" desktop\CoCo3.pb /EXE build\CoCo3.exe /THREAD /DPIAWARE
build\CoCo3.exe [--rom coco3.rom] [--cart disk11.rom] [--disk0 games.dsk] [--new-disk1 blank.dsk]
tools\desktop_check.ps1          # build, then the console checks below
```

The window shows the CoCo's screen (4:3, scaled to fit), the 6809's registers, the GIME's registers, MMU
and palette, a disassembly from the PC, a memory view, the log, Run/Pause/Step/Frame/Reset/Full speed/Mute,
and the drives. Typing goes to the CoCo keyboard (arrows, Esc = BREAK, Home = CLEAR, F1, F2); F5 run/pause,
F10 one instruction, F11 one frame, F3 reset, F8 full speed, F9 mute. Sound plays through Windows.
`--log N` runs N frames with no window and prints the CoCo's screen as text; `--type` / `--type-file` type
into it; `--shot file.png N` saves the window after N frames.

Measured on this PC (2026-10-23, `tools/desktop_check.ps1`): BASIC boots and runs a typed program; BASIC's
10-second TIMER loop counts **910**, the same as on the Pico W (`tests/timer.txt`); a program SAVEd to a new
`.DSK` loads and runs in a second session. Unthrottled, the console runs 280-410 MHz of 6809 cycles (300-450x a
real CoCo 3); the window holds the real machine's 59.92 frames a second.

## The PureMetal demo (demo/)

`demo/coco3demo.coco3` is a PureMetal program for the CoCo 3 itself, built with PureMetalForge's
"Tandy Color Computer 3 (Disk BASIC)" board into a Disk BASIC disk: a 320 x 192 x 16 GIME picture held in a
PureMetal array, a title in large letters, palette bands rolling up the screen, and a tune on the 6-bit DAC
played from the GIME's fast timer on FIRQ. `LOADM"COCO3DEM":EXEC` from the disk in drive 0 (on the Pico,
put the `.dsk` in a slot with `make_disk_region.py`).

## Sources

MAME's `gime.cpp`, `coco3.cpp`, `coco.cpp`, `coco_fdc.cpp` and `mc6847.cpp` (BSD-3-Clause) were read
for the hardware's behaviour; the 64 composite colours are MAME's table (`src/video.pmi`). No MAME code
is compiled into the firmware.
