; Tandy Color Computer 3 for the desktop - PureBasic, drawn with the Neon Arcade Display Engine.
; The same machine as the Pico version: src/machine.pmi, video.pmi, keyboard.pmi, sound.pmi, disk.pmi
; and coco3.pmi are compiled here unchanged; the PC gives it 512 KB of RAM and .DSK files for the FD-502.
;
; BUILD (x64, from PowerShell, C back end):
;   (Neon-Arcade-Dispay-Engine and 6809EmulatorPicoSeries cloned beside this repository; from its folder:)
;   mkdir build
;   & "C:\Program Files\PureBasic\Compilers\pbcompilerc.exe" desktop\CoCo3.pb /EXE build\CoCo3.exe /THREAD /DPIAWARE
;       [/CONSTANT GL_ENGINE_DIR$=C:/path/to/engine/]   (default below)
;       [/CONSTANT COCO_CPU_DIR$=C:/path/to/6809EmulatorPicoSeries/desktop/]   (default: beside this repo)
; RUN:
;   CoCo3.exe [--rom coco3.rom] [--cart disk11.rom|--no-cart] [--disk0 file.dsk ... --disk3] [--new-disk0 file.dsk]
;       the window. The ROMs default to a folder roms beside CoCo3.exe (tools/build_roms.ps1 leaves them in build\roms).
;   CoCo3.exe ... --log N [--type "text"] [--fast]   no window: N frames, a status line a second, the
;       screen as text at the end (--type types into the CoCo after boot, \n for ENTER).
;   CoCo3.exe ... --shot file.png N [--type "text"]  the window for N frames, then its picture, then exit.
;   CoCo3.exe ... --wav file.wav [--mute]  also writes what the sound device was given (48 kHz mono) and
;       file.wav.txt (underruns, skips, the reader's step, both threads' stalls); --mute plays silence.
; KEYS: the controls table, desktop/controls.pbi (the Controls tab shows it; --controls-md writes it as Markdown).
;   CoCo3.exe ... --fullscreen-test log [shot.png]  full screen checked by posted keys; exits with the failures.
; The ROMs are Tandy's: none are in the repository.

EnableExplicit

CompilerIf Not Defined(GL_ENGINE_DIR$, #PB_Constant)
  #GL_ENGINE_DIR$ = #PB_Compiler_FilePath + "../../Neon-Arcade-Dispay-Engine/"   ; cloned beside this repository
CompilerEndIf
XIncludeFile #GL_ENGINE_DIR$ + "GlTypes.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUtilities.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlMath.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlSpriteFunctions.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUI.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUIChrome.pbi"
; this frame is not drawn through DrawRetroCRT: with the CRT on (the engine's default) every pointer
; position is bent by its barrel curve - up to 28 px at 125%, worst at the top and bottom of the window
UI_UseCRT = #False
CompilerIf Defined(PLANT_CRT, #PB_Constant)
  UI_UseCRT = #True   ; only to see --pointer-test fail
CompilerEndIf
UsePNGImageEncoder()

; The log (host.pbi): Say takes a string here; on a Pico it takes a string's address (say_decl.pmi).
Declare HostOut(t$)
Declare Num(v.i)
Declare Eol()
Macro Say(t)
  HostOut(t)
EndMacro
; A Pico's ProcedureRAM (code run from SRAM, video_portable.pmi) is an ordinary procedure on a PC.
Macro ProcedureRAM
  Procedure
EndMacro

; The machine, as on the Pico, with a PC's memory.
#COCO_RAM_PAGES = 64                     ; 512 KB
#COCO_RAM_LAYOUT = 1                     ; one array
#VIDEO_RGB = 0
CompilerIf Not Defined(COCO_CPU, #PB_Constant)
  #COCO_CPU = 1
CompilerEndIf
CompilerIf #COCO_CPU = 1
  CompilerIf Not Defined(COCO_CPU_DIR$, #PB_Constant)
    #COCO_CPU_DIR$ = #PB_Compiler_FilePath + "../../6809EmulatorPicoSeries/desktop/"
  CompilerEndIf
  #CPU_TIMING = 1                        ; CpuRun's budget is E cycles
  #CPU_ASM_TAIL = 0
  XIncludeFile #COCO_CPU_DIR$ + "cpu6809.pbi"
  XIncludeFile #COCO_CPU_DIR$ + "disasm6809.pbi"
  XIncludeFile "../src/cpu6809_glue.pmi"
CompilerElse
  XIncludeFile "../src/cpu_none.pmi"
CompilerEndIf
XIncludeFile "../src/machine.pmi"
XIncludeFile "../src/video.pmi"
XIncludeFile "../src/video_portable.pmi"
XIncludeFile "../src/keyboard.pmi"
XIncludeFile "../src/sound.pmi"
XIncludeFile "../src/disk.pmi"
XIncludeFile "../src/coco3.pmi"
XIncludeFile "host.pbi"
XIncludeFile "controls.pbi"

#SCR_W = 640
#SCR_H = 480                             ; shown 640 x 480 (4:3): 240 lines, each drawn twice by the GPU
#TEX_H = 240
#FRAME_US = 16688                        ; 262 x 1824 GIME clocks at 28.636363 MHz

Global Dim ScrPix.l(#SCR_W * #TEX_H)     ; RGBA, bottom row first (as the engine samples it)
Global ScrDirty.i = 1
Global EmuRunning.i = 1, EmuFull.i, EmuFrames.q, EmuStop$
Global SpeedMark.q, SpeedCycles.q, SpeedFrames.q, SpeedKhz.f, SpeedFps.f, SpeedX.f
Global TypeText$, TypeAt.i = 240

Procedure.s H2(v.i) : ProcedureReturn RSet(Hex(v & $FF), 2, "0") : EndProcedure
Procedure.s H4(v.i) : ProcedureReturn RSet(Hex(v & $FFFF), 4, "0") : EndProcedure

; The 240 lines of the picture into ScrPix.
Procedure ScreenRender()
  Protected line.i, x.i, c.l, *p.Long, i.i
  Protected Dim lut.l(16)
  For line = 0 To 239
    VideoRenderSamples(line)
    For i = 0 To 16
      c = VideoRgb(i) : lut(i) = $FF000000 | ((c & $FF) << 16) | (c & $FF00) | ((c >> 16) & $FF)
    Next
    *p = @ScrPix((#TEX_H - 1 - line) * #SCR_W)
    For x = 0 To 639
      *p\l = lut(VideoSamples(x)) : *p + 4
    Next
  Next
EndProcedure

; Keys typed by --type / --type-file, after the boot screen has come up: one line at a time, the next only
; when the last line's keys are all in and the CoCo has had a second to act on it (BASIC polls the keyboard
; while it runs a command - for a pause key - and a key pressed then is lost, as on the real machine).
Global TypeIdleSince.i
Procedure TypeFeed()
  Protected i.i, c.i, line$, cut.i
  If TypeText$ = "" Or EmuFrames < TypeAt : ProcedureReturn : EndIf
  If KeyPending() Or KeyState : TypeIdleSince = EmuFrames : ProcedureReturn : EndIf
  If EmuFrames - TypeIdleSince < 60 : ProcedureReturn : EndIf
  cut = FindString(TypeText$, "\n")
  If cut : line$ = Left(TypeText$, cut + 1) : TypeText$ = Mid(TypeText$, cut + 2) : Else : line$ = TypeText$ : TypeText$ = "" : EndIf
  For i = 1 To Len(line$)
    c = Asc(Mid(line$, i, 1))
    If c = '\' And Mid(line$, i + 1, 1) = "n" : c = 13 : i + 1 : EndIf
    If c = '\' And Mid(line$, i + 1, 1) = "q" : c = 34 : i + 1 : EndIf    ; a quote (a command line drops real ones)
    KeyPut(c)
  Next
  TypeIdleSince = EmuFrames
EndProcedure

Global EmuCpuUs.q, EmuSndUs.q
Declare.q MicroNow()
Procedure EmuFrame()
  Protected t.q = MicroNow()
  CocoFrame()
  ScrDirty = 1
  EmuCpuUs + MicroNow() - t
  KeyFrame()
  EmuFrames + 1
  TypeFeed()
  t = MicroNow()
  HostSoundPump()
  EmuSndUs + MicroNow() - t
  CompilerIf #COCO_CPU = 1
    If CpuStopped And EmuStop$ = "" : EmuStop$ = "6809 stopped: opcode $" + Hex(CpuBadOpcode) + " at $" + H4(CpuPC) : EndIf
  CompilerEndIf
EndProcedure

; One instruction, at the machine's time (paused only).
Procedure EmuStep()
  CompilerIf #COCO_CPU = 1
    Protected used.i
    CocoFolded = 0
    used = CocoCpuRun(1)
    CocoLinePos = CocoLinePos + (used - CocoFolded) * CocoCycleClocks : CocoFolded = 0
    If CocoLinePos >= #GIME_LINE_CLOCKS
      CocoLinePos = CocoLinePos - #GIME_LINE_CLOCKS : CocoEndLine() : SoundCatchUp(GimeNow)
      If CocoLine = 0 : KeyFrame() : EmuFrames + 1 : EndIf
    EndIf
    ScrDirty = 1
  CompilerEndIf
EndProcedure

Procedure SpeedUpdate()
  Protected now.q = ElapsedMilliseconds(), dt.q = now - SpeedMark
  If dt < 1000 : ProcedureReturn : EndIf
  SpeedKhz = (CpuCycles - SpeedCycles) / dt
  SpeedFps = (EmuFrames - SpeedFrames) * 1000.0 / dt
  If CocoFast : SpeedX = SpeedKhz / 1789.773 : Else : SpeedX = SpeedKhz / 894.886 : EndIf
  SpeedMark = now : SpeedCycles = CpuCycles : SpeedFrames = EmuFrames
EndProcedure

Procedure.s StatusLine()
  ProcedureReturn "frames " + Str(EmuFrames) + "  " + StrF(SpeedFps, 1) + " fps  " + StrF(SpeedKhz, 0) + " kHz  " +
                  StrF(SpeedX, 2) + "x a real CoCo 3 at " + StringField("0.89|1.79", CocoFast + 1, "|") + " MHz" +
                  "  pc $" + H4(CocoCpuPc()) + "  sound underruns " + Str(HostSndUnderruns)
EndProcedure

Procedure.s ScreenText()
  Protected t$
  HostLine$ = "" : CocoTextDump() : t$ = HostLog$
  ProcedureReturn t$
EndProcedure

; ---------------------------------------------------------------- console runs (proof without a window)

Procedure ConsoleRun(frames.i)
  Protected i.i, t0.q = ElapsedMilliseconds()
  HostConsole = 1
  SpeedMark = t0
  For i = 1 To frames
    EmuFrame()
    If ElapsedMilliseconds() - SpeedMark >= 1000 : SpeedUpdate() : PrintN(StatusLine()) : EndIf
    If EmuStop$ <> "" : PrintN(EmuStop$) : Break : EndIf
  Next
  PrintN("done: " + Str(EmuFrames) + " frames in " + Str(ElapsedMilliseconds() - t0) + " ms unpaced, " +
         StrF(CpuCycles / 1000.0 / (ElapsedMilliseconds() - t0 + 1), 1) + " MHz of 6809 cycles = " +
         StrF(CpuCycles / 894.886 / (ElapsedMilliseconds() - t0 + 1), 1) + "x a real CoCo 3 at 0.89 MHz")
  PrintN("keyboard: typed " + Str(KeyTyped) + " queued " + Str(KeyPending()) + " state " + Str(KeyState) + " scans " + Str(KeyScans) +
         " held for " + Str(CocoFrames - KeyStart) + " frames; matrix " + Str(CocoKeys(0)) + "," + Str(CocoKeys(1)) + "," + Str(CocoKeys(2)) + "," + Str(CocoKeys(7)) +
         "; cpu pc $" + H4(CocoCpuPc()) + " wait " + Str(CpuWaiting) + " sync " + Str(CpuSyncing) + " stopped " + Str(CpuStopped))
  CocoTextDump()
EndProcedure

; ---------------------------------------------------------------- the window

Global Win.i, Gl.i, ScreenTex.l, ScreenSprite.GLSprite, FontsBuilt.i
Global MouseDown.b, Wheel.i, KeyCode.i, KeyChar.i, PhysW.i, PhysH.i, RightTab.i, MemTop.i
Global ShotPath$, ShotFrames.i, QpcFreq.q
Global Dim PartUs.q(7), Dim PartShown.f(7), PartLoops.q, ShowTiming.i, PassFrames.i

Procedure.q MicroNow()
  Protected c.q
  If QpcFreq = 0 : QueryPerformanceFrequency_(@QpcFreq) : EndIf
  QueryPerformanceCounter_(@c)
  ProcedureReturn c * 1000000 / QpcFreq
EndProcedure

; The fonts at their logical size * the display scale (Neon_UIScale), rebuilt when the scale changes.
Procedure BuildFonts()
  If FontsBuilt
    FreeGLFont(*Neon_FontUI) : FreeGLFont(*Neon_FontSmall) : FreeGLFont(*Neon_FontBold) : FreeGLFont(*Neon_FontMono)
  EndIf
  FontsBuilt = 1
  *Neon_FontUI = Neon_CreateFontPx("Segoe UI", Round(Neon_S(14), #PB_Round_Nearest))
  *Neon_FontSmall = Neon_CreateFontPx("Segoe UI", Round(Neon_S(12), #PB_Round_Nearest))
  *Neon_FontBold = Neon_CreateFontPx("Segoe UI", Round(Neon_S(15), #PB_Round_Nearest), #PB_Font_Bold)
  *Neon_FontMono = Neon_CreateFontPx("Consolas", Round(Neon_S(13), #PB_Round_Nearest))
  GLFontSetSnapToPixel(*Neon_FontUI, #True) : GLFontSetSnapToPixel(*Neon_FontSmall, #True)
  GLFontSetSnapToPixel(*Neon_FontBold, #True) : GLFontSetSnapToPixel(*Neon_FontMono, #True)
EndProcedure

; The GL gadget fills the inner client from (0,0); the canvas and the viewport are its PHYSICAL size
; (GetClientRect), Util_WinWidth/Height its logical size. No GL_HandleResize: this is a 1:1 window.
Procedure MeasureWindow()
  Protected r.RECT, w.i = WindowWidth(Win, #PB_Window_InnerCoordinate), h.i = WindowHeight(Win, #PB_Window_InnerCoordinate), s.f
  If GadgetX(Gl) <> 0 Or GadgetY(Gl) <> 0 Or GadgetWidth(Gl) <> w Or GadgetHeight(Gl) <> h : ResizeGadget(Gl, 0, 0, w, h) : EndIf
  GetClientRect_(WindowID(Win), @r)
  PhysW = r\right - r\left : PhysH = r\bottom - r\top
  If PhysW < 1 : PhysW = 1 : EndIf
  If PhysH < 1 : PhysH = 1 : EndIf
  Util_BaseWidth = PhysW : Util_BaseHeight = PhysH
  Util_WinWidth = w : Util_WinHeight = h
  GL_ViewportX = 0 : GL_ViewportY = 0 : GL_ViewportW = PhysW : GL_ViewportH = PhysH
  ; the display scale s = physical / logical client width, MEASURED (the engine's GlUIChrome.pbi section 5a):
  ; the chrome (Neon_UIScale) and the fonts follow it, and change with it on a monitor with another scale
  s = 1.0
  If w > 0 : s = PhysW / w : EndIf
  If s <= 0 : s = 1.0 : EndIf
  If FontsBuilt = 0 Or Abs(s - Neon_UIScale) > 0.005 : Neon_UIScale = s : BuildFonts() : EndIf
EndProcedure

; ---------------------------------------------------------------- --pointer-test controls
; Where each control was last drawn, in canvas units (physical pixels), and the control a synthetic press
; landed on - under the test a press is recorded, never acted on.
Global PtOn.i, PtClicked$
Structure CtlRect : x.f : y.f : w.f : h.f : EndStructure
Global NewMap Ctl.CtlRect()
Procedure CtlSet(name$, x.f, y.f, w.f, h.f)
  Ctl(name$)\x = x : Ctl()\y = y : Ctl()\w = w : Ctl()\h = h
EndProcedure
Procedure.b Btn(name$, x.f, y.f, w.f, h.f, label.s, lit.b = #False, enabled.b = #True)
  CtlSet(name$, x, y, w, h)
  If Neon_Button(x, y, w, h, label, lit, enabled)
    If PtOn : PtClicked$ = name$ : ProcedureReturn #False : EndIf
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure ScreenTextureInit()
  glGenTextures_(1, @ScreenTex)
  glBindTexture_(#GL_TEXTURE_2D, ScreenTex)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MIN_FILTER, #GL_LINEAR)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MAG_FILTER, #GL_LINEAR)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_S, #GL_CLAMP_TO_EDGE)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_T, #GL_CLAMP_TO_EDGE)
  glTexImage2D_(#GL_TEXTURE_2D, 0, #GL_RGBA, #SCR_W, #TEX_H, 0, #GL_RGBA, #GL_UNSIGNED_BYTE, @ScrPix(0))
  ScreenSprite\TextureID = ScreenTex : ScreenSprite\Width = #SCR_W : ScreenSprite\Height = #SCR_H
EndProcedure

Procedure ScreenTextureUpload()
  If ScrDirty = 0 : ProcedureReturn : EndIf
  ScrDirty = 0
  Protected t.q = MicroNow()
  ScreenRender()
  PartUs(7) + MicroNow() - t
  glBindTexture_(#GL_TEXTURE_2D, ScreenTex)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, #SCR_W, #TEX_H, #GL_RGBA, #GL_UNSIGNED_BYTE, @ScrPix(0))
EndProcedure

Procedure.s CCFlags(cc.i)
  Protected s$, i.i, names$ = "EFHINZVC"
  For i = 0 To 7
    If cc & (128 >> i) : s$ + Mid(names$, i + 1, 1) : Else : s$ + "." : EndIf
  Next
  ProcedureReturn s$
EndProcedure

Procedure.i CpuPeek(a.i)
  Protected page.i = CpuRdMap((a >> 8) & 255)
  If page = 0 Or (a & $FFFF) >= $FF00 : ProcedureReturn -1 : EndIf
  CompilerIf #COCO_CPU = 1
    ProcedureReturn PeekA(page + (a & $FFFF))
  CompilerElse
    ProcedureReturn PeekA(page + (a & $FF))
  CompilerEndIf
EndProcedure

Procedure DrawRegisters(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), ty.f = y + Neon_S(34), tx.f = x + Neon_S(12), i.i, m$
  Neon_Panel(x, y, w, h, "6809", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB, Neon_S(26))
  CompilerIf #COCO_CPU = 1
    Neon_Text(*Neon_FontMono, tx, ty, "A  " + H2(CpuA) + "   B  " + H2(CpuB) + "   D  " + H4((CpuA << 8) | CpuB) + "   DP " + H2(CpuDPage >> 8), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
    Neon_Text(*Neon_FontMono, tx, ty, "X  " + H4(CpuX) + " Y  " + H4(CpuY) + " U  " + H4(CpuU) + " S  " + H4(CpuS), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
    Neon_Text(*Neon_FontMono, tx, ty, "PC " + H4(CpuPC) + "   CC " + CCFlags(CpuGetCC()), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB) : ty + lh
    Neon_Text(*Neon_FontMono, tx, ty, "IRQ " + Str(CpuIrqLine) + "  FIRQ " + Str(CpuFirqLine) + "  CWAI " + Str(CpuWaiting) + "  SYNC " + Str(CpuSyncing), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  CompilerElse
    Neon_Text(*Neon_FontMono, tx, ty, "no CPU in this build (#COCO_CPU = 0)", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh * 4
  CompilerEndIf
  ty + lh * 0.4
  Neon_Text(*Neon_FontMono, tx, ty, "GIME $FF90 " + H2(Gime(0)) + " $FF91 " + H2(Gime(1)) + " $FF98 " + H2(Gime(8)) + " $FF99 " + H2(Gime(9)), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  m$ = "MMU " : For i = 0 To 7 : m$ + H2(GimeMmu(i + (Gime(1) & 1) * 8)) + " " : Next
  Neon_Text(*Neon_FontMono, tx, ty, m$ + " task " + Str(Gime(1) & 1), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  m$ = "PAL " : For i = 0 To 15 : m$ + H2(GimePal(i)) : Next
  Neon_Text(*Neon_FontMono, tx, ty, m$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, tx, ty, "IRQ pend " + H2(GimeIrqPending) + " FIRQ pend " + H2(GimeFirqPending) + " line " + Str(CocoLine), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontMono, tx, ty, "disk reads " + Str(DiskReads) + " writes " + Str(DiskWrites) + " errors " + Str(DiskWriteErrors), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
EndProcedure

Procedure DrawMemory(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), ty.f = y + Neon_S(6), rows.i, r.i, k.i, a.i, v.i, line$, asc$
  rows = (h - Neon_S(12)) / lh
  CtlSet("memory pane", x, y, w, h)
  If Neon_Hit(x, y, w, h) And Neon_Wheel : MemTop - Neon_Wheel * 3 : EndIf
  If MemTop < 0 : MemTop = 0 : EndIf
  If MemTop > 4096 - rows : MemTop = 4096 - rows : EndIf
  For r = 0 To rows - 1
    a = (MemTop + r) * 16 : line$ = H4(a) + "  " : asc$ = ""
    For k = 0 To 15
      v = CpuPeek(a + k)
      If v < 0 : line$ + "-- " : asc$ + " " : Else : line$ + H2(v) + " " : If v >= 32 And v < 127 : asc$ + Chr(v) : Else : asc$ + "." : EndIf : EndIf
    Next
    Neon_Text(*Neon_FontMono, x + Neon_S(10), ty, line$ + " " + asc$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Next
EndProcedure

Procedure DrawDisassembly(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), ty.f = y + Neon_S(6), rows.i, r.i, a.i, t$, k.i, b$, n.i
  rows = (h - Neon_S(12)) / lh
  CompilerIf #COCO_CPU = 1
    a = CpuPC
    For r = 0 To rows - 1
      If a >= $FF00 Or CpuRdMap((a >> 8) & 255) = 0
        Neon_Text(*Neon_FontMono, x + Neon_S(14), ty, H4(a) + "  (I/O page: not read)", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
        Break
      EndIf
      t$ = CpuDisasm(a) : n = CpuDisasmLen : If n < 1 : n = 1 : EndIf
      b$ = "" : For k = 0 To n - 1 : b$ + H2(CpuPeek(a + k)) : Next
      If r = 0 : Neon_Box(x + Neon_S(2), ty - Neon_S(1), w - Neon_S(4), lh, 0.20, 0.22, 0.26) : EndIf
      Neon_Text(*Neon_FontMono, x + Neon_S(14), ty, H4(a) + "  " + LSet(b$, 10) + t$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
      ty + lh : a = (a + n) & $FFFF
    Next
  CompilerEndIf
EndProcedure

Procedure DrawLog(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), ty.f, n.i, i.i, rows.i
  rows = (h - Neon_S(12)) / lh
  n = CountString(HostLog$, #LF$)
  ty = y + Neon_S(6)
  For i = n - rows + 1 To n
    If i >= 1 : Neon_Text(*Neon_FontMono, x + Neon_S(10), ty, StringField(HostLog$, i, #LF$), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB) : EndIf
    ty + lh
  Next
EndProcedure

; The Controls tab: the controls table (controls.pbi), the PC key beside what it is on the CoCo 3 or in the
; window; the wheel scrolls it when the pane is shorter than the table.
Global CtlTop.i
Procedure DrawControlsTab(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontSmall) + Neon_S(4), ty.f, rows.i, n.i, i.i, r.f, g.f, b.f
  rows = (h - Neon_S(12)) / lh : n = ListSize(Controls())
  If Neon_Hit(x, y, w, h) And Neon_Wheel : CtlTop - Neon_Wheel : EndIf
  If CtlTop > n - rows : CtlTop = n - rows : EndIf
  If CtlTop < 0 : CtlTop = 0 : EndIf
  ty = y + Neon_S(6)
  ForEach Controls()
    If i >= CtlTop And i < CtlTop + rows
      r = Neon_C_TextR : g = Neon_C_TextG : b = Neon_C_TextB
      If Controls()\kind = #CTL_ACTION : r = Neon_C_AmbR : g = Neon_C_AmbG : b = Neon_C_AmbB : EndIf
      If Controls()\kind = #CTL_NOTE : r = Neon_C_DimR : g = Neon_C_DimG : b = Neon_C_DimB : EndIf
      Neon_Text(*Neon_FontSmall, x + Neon_S(14), ty, Controls()\pc$, r, g, b)
      Neon_Text(*Neon_FontSmall, x + Neon_S(200), ty, Controls()\coco$, r, g, b)
      ty + lh
    EndIf
    i + 1
  Next
EndProcedure

; ---------------------------------------------------------------- full screen
; The Full screen button or F11: a borderless window over the monitor the window is on (no display-mode
; change) showing only the CoCo's picture - 640 x 240 samples shown 4:3, as the NTSC set shows them - as
; large as fits and centred, black around it. Emulation, sound and the 60 Hz frame rate are the window's.
; Esc leaves (it is BREAK only in the window; End is BREAK in both), and the window comes back exactly as
; it was. The pointer hides after two idle seconds.
Global FullScreen.i, FsStyle.i, FsPlacement.WINDOWPLACEMENT, FsCursorHidden.i, FsMouseX.i, FsMouseY.i, FsMouseMs.q
Global FsViewX.f, FsViewY.f, FsViewW.f, FsViewH.f

Procedure FsShowCursor(show.i)
  If show And FsCursorHidden : ShowCursor_(#True) : FsCursorHidden = 0 : EndIf
  If show = 0 And FsCursorHidden = 0 : ShowCursor_(#False) : FsCursorHidden = 1 : EndIf
EndProcedure

Procedure EnterFullScreen()
  Protected hwnd.i = WindowID(Win), mi.MONITORINFO
  If FullScreen : ProcedureReturn : EndIf
  FsPlacement\length = SizeOf(WINDOWPLACEMENT) : GetWindowPlacement_(hwnd, @FsPlacement)
  FsStyle = GetWindowLongPtr_(hwnd, #GWL_STYLE)
  mi\cbSize = SizeOf(MONITORINFO) : GetMonitorInfo_(MonitorFromWindow_(hwnd, 2), @mi)   ; 2: the nearest monitor
  SetWindowLongPtr_(hwnd, #GWL_STYLE, FsStyle & ~(#WS_CAPTION | #WS_THICKFRAME | #WS_MINIMIZEBOX | #WS_MAXIMIZEBOX | #WS_SYSMENU))
  SetWindowPos_(hwnd, #HWND_TOP, mi\rcMonitor\left, mi\rcMonitor\top, mi\rcMonitor\right - mi\rcMonitor\left, mi\rcMonitor\bottom - mi\rcMonitor\top, #SWP_FRAMECHANGED | #SWP_NOOWNERZORDER | #SWP_SHOWWINDOW)
  FullScreen = 1 : FsMouseMs = ElapsedMilliseconds()
  MeasureWindow()
EndProcedure

Procedure LeaveFullScreen()
  Protected hwnd.i = WindowID(Win)
  If FullScreen = 0 : ProcedureReturn : EndIf
  SetWindowLongPtr_(hwnd, #GWL_STYLE, FsStyle)
  SetWindowPlacement_(hwnd, @FsPlacement)
  SetWindowPos_(hwnd, 0, 0, 0, 0, 0, #SWP_FRAMECHANGED | #SWP_NOMOVE | #SWP_NOSIZE | #SWP_NOZORDER | #SWP_NOOWNERZORDER)
  FullScreen = 0 : FsShowCursor(1)
  MeasureWindow()
EndProcedure

Procedure DrawFullScreen()
  Protected a.f = #SCR_W / #SCR_H, vw.f, vh.f, mx.i, my.i
  vw = PhysW : vh = vw / a
  If vh > PhysH : vh = PhysH : vw = vh * a : EndIf
  vw = Round(vw, #PB_Round_Nearest) : vh = Round(vh, #PB_Round_Nearest)
  FsViewW = vw : FsViewH = vh : FsViewX = Round((PhysW - vw) / 2, #PB_Round_Down) : FsViewY = Round((PhysH - vh) / 2, #PB_Round_Down)
  ScreenTextureUpload()
  DrawGLSprite(@ScreenSprite, FsViewX, FsViewY, 0.0, vw / #SCR_W, 1.0, 1.0, 1.0, 1.0, #True, -1, -1, -1, -1, #True)
  ; the pointer hides after two seconds without moving, and shows again when it moves
  mx = WindowMouseX(Win) : my = WindowMouseY(Win)
  If mx <> FsMouseX Or my <> FsMouseY : FsMouseX = mx : FsMouseY = my : FsMouseMs = ElapsedMilliseconds() : FsShowCursor(1) : EndIf
  If ElapsedMilliseconds() - FsMouseMs > 2000 : FsShowCursor(0) : EndIf
EndProcedure

; The window's own keys and buttons.
Procedure WindowAction(act.i)
  Select act
    Case #ACT_RUNPAUSE : EmuRunning ! 1
    Case #ACT_STEP : If EmuRunning = 0 : EmuStep() : EndIf
    Case #ACT_FRAME : If EmuRunning = 0 : EmuFrame() : EndIf
    Case #ACT_RESET : CocoReset() : CocoCpuReset()
    Case #ACT_FULLSPEED : EmuFull ! 1
    Case #ACT_MUTE : HostSndMuted ! 1
    Case #ACT_FULLSCREEN : If FullScreen : LeaveFullScreen() : Else : EnterFullScreen() : EndIf
    Case #ACT_LEAVEFULL : LeaveFullScreen()
  EndSelect
EndProcedure

; A key the gadget reported as a key code (characters come as #PB_EventType_Input): the controls table's
; CoCo key or window key, or ALT / CTRL held with a letter or digit (both held is AltGr: a character).
Global HostKeyLog$   ; the bytes this put in the queue, for --fullscreen-test
Procedure HostKeyDown(k.i)
  Protected *c.Control = ControlFind(k, FullScreen), held.i, mod.i
  If *c
    If *c\kind = #CTL_ACTION : WindowAction(*c\value) : Else : KeyPut(*c\value) : HostKeyLog$ + Str(*c\value) + " " : EndIf
    ProcedureReturn
  EndIf
  If (k >= #PB_Shortcut_A And k <= #PB_Shortcut_Z) Or (k >= #PB_Shortcut_0 And k <= #PB_Shortcut_9)
    ForEach Controls()
      If Controls()\kind = #CTL_MOD And GetKeyState_(Controls()\pcKey) & $8000 : held + 1 : mod = Controls()\value : EndIf
    Next
    If held = 1 : KeyPut(mod) : KeyPut(k) : HostKeyLog$ + Str(mod) + " " + Str(k) + " " : EndIf
  EndIf
EndProcedure

Procedure DrawControls(x.f, y.f, w.f, h.f)
  Protected bx.f = x + Neon_S(12), by.f = y + Neon_S(36), bh.f = Neon_S(28), d.i, p$, r$
  Neon_Panel(x, y, w, h, "Tandy Color Computer 3 - 512 KB, Disk BASIC", Neon_C_VioR, Neon_C_VioG, Neon_C_VioB, Neon_S(26))
  If Btn("Run", bx, by, Neon_S(64), bh, "Run", EmuRunning, Bool(EmuRunning = 0)) : EmuRunning = 1 : EndIf : bx + Neon_S(70)
  If Btn("Pause", bx, by, Neon_S(64), bh, "Pause", #False, EmuRunning) : EmuRunning = 0 : EndIf : bx + Neon_S(70)
  If Btn("Step", bx, by, Neon_S(64), bh, "Step", #False, Bool(EmuRunning = 0)) : EmuStep() : EndIf : bx + Neon_S(70)
  If Btn("Frame", bx, by, Neon_S(64), bh, "Frame", #False, Bool(EmuRunning = 0)) : EmuFrame() : EndIf : bx + Neon_S(70)
  If Btn("Reset", bx, by, Neon_S(64), bh, "Reset") : CocoReset() : CocoCpuReset() : EndIf : bx + Neon_S(70)
  If Btn("Full speed", bx, by, Neon_S(88), bh, "Full speed", EmuFull) : EmuFull ! 1 : EndIf : bx + Neon_S(94)
  If Btn("Mute", bx, by, Neon_S(64), bh, "Mute", HostSndMuted) : HostSndMuted ! 1 : EndIf
  by + bh + Neon_S(8) : bx = x + Neon_S(12)
  For d = 0 To 1
    If Btn("Drive " + Str(d), bx, by, Neon_S(110), bh, "Drive " + Str(d) + "...")
      p$ = OpenFileRequester("Disk for drive " + Str(d), "", "CoCo disks (*.dsk)|*.dsk|All files|*.*", 0)
      If p$ <> "" : r$ = HostDiskMount(d, p$) : If r$ <> "" : HostOut(r$) : Eol() : EndIf : EndIf
    EndIf
    Neon_Text(*Neon_FontSmall, bx + Neon_S(116), by + Neon_S(7), GetFilePart(HostDiskPath$(d)), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
    bx + w / 2 - Neon_S(6)
  Next
  by + bh + Neon_S(8) : bx = x + Neon_S(12)
  If Btn("Full screen", bx, by, Neon_S(124), bh, "Full screen  F11") : WindowAction(#ACT_FULLSCREEN) : EndIf : bx + Neon_S(130)
  If Btn("Controls", bx, by, Neon_S(88), bh, "Controls", Bool(RightTab = 3)) : RightTab = 3 : EndIf
  by + bh + Neon_S(10)
  Neon_Text(*Neon_FontUI, x + Neon_S(12), by, StatusLine(), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  If EmuStop$ <> "" : Neon_Text(*Neon_FontUI, x + Neon_S(12), by + Neon_S(20), EmuStop$, Neon_C_RedR, Neon_C_RedG, Neon_C_RedB) : EndIf
EndProcedure

; ---------------------------------------------------------------- --pointer-test
; The real pointer is shared with everyone on this desktop, so it is never moved: the chrome is driven with
; synthetic positions in the units WindowMouseX/Y give a DPI-aware window (physical pixels), through the same
; Neon_ChromeBeginFrame call. For every control four points: just inside its top-left and its bottom-right
; corner (a press must land on it), just right of it and just below it (a press must not). Every frame
; Neon_MX / Neon_MY must read the point back unbent. Controls at the top of the window (the buttons), in the
; middle (the tab strip) and at the bottom (the memory pane, which a wheel turn over it must scroll).
Global PtLog$, PtFile$, PtX.f, PtY.f, PtDown.i, PtWheel.i, PtCase.i, PtPoint.i, PtFrame.i, PtFails.i, PtPoints.i, PtWorst.f, PtDone.i
Global PtCount.i, Dim PtName$(20)

Procedure PtInit()
  Protected n$ = "Run|Pause|Step|Frame|Reset|Full speed|Mute|Drive 0|Drive 1|Full screen|Controls|tab 0|tab 1|tab 2|tab 3|memory pane", i.i
  PtCount = CountString(n$, "|") + 1
  For i = 0 To PtCount - 1 : PtName$(i) = StringField(n$, i + 1, "|") : Next
EndProcedure

Procedure.i PtRect(name$, *r.CtlRect)
  Protected *row.Neon_TabRowLayout, i.i
  If Left(name$, 4) = "tab "
    If FindMapElement(Neon_TabLayout(), "300") = 0 : ProcedureReturn 0 : EndIf
    *row = @Neon_TabLayout() : i = Val(Mid(name$, 5))
    If i >= *row\Count : ProcedureReturn 0 : EndIf
    ; the row's last pixel is the strip's underline, not a tab
    *r\x = *row\X(i) : *r\w = *row\W(i) : *r\y = *row\Y : *r\h = *row\H - 1
    ProcedureReturn 1
  EndIf
  If FindMapElement(Ctl(), name$) = 0 : ProcedureReturn 0 : EndIf
  CopyStructure(@Ctl(), *r, CtlRect)
  ProcedureReturn 1
EndProcedure

; One step, after each frame is drawn.
Procedure PtStep()
  Protected r.CtlRect, name$, inside.i, got$, ok.i, f.i, hit.i
  If PtCase >= PtCount
    PtLog$ + "pointer-test: " + Str(PtPoints) + " points on " + Str(PtCount) + " controls, " + Str(PtFails) + " failures, scale " +
             StrF(Neon_UIScale, 2) + ", canvas " + Str(Util_BaseWidth) + "x" + Str(Util_BaseHeight) + " physical, window " +
             Str(Util_WinWidth) + "x" + Str(Util_WinHeight) + " logical, UI_UseCRT " + Str(UI_UseCRT) +
             ", worst pointer read-back error " + StrF(PtWorst, 2) + " px" + #LF$
    f = CreateFile(#PB_Any, PtFile$)
    If f : WriteString(f, PtLog$) : CloseFile(f) : EndIf
    PtDone = 1
    ProcedureReturn
  EndIf
  name$ = PtName$(PtCase)
  If PtFrame > 1
    If Abs(Neon_MX - PtX) > PtWorst : PtWorst = Abs(Neon_MX - PtX) : EndIf
    If Abs(Neon_MY - PtY) > PtWorst : PtWorst = Abs(Neon_MY - PtY) : EndIf
  EndIf
  PtFrame + 1
  Select PtFrame
    Case 1                                       ; the pane that shows the control, the pointer away
      If name$ = "memory pane" : RightTab = 1 : Else : RightTab = 0 : EndIf
      EmuRunning = Bool(name$ = "Pause")         ; Pause is enabled only while running, Run/Step/Frame only paused
      PtX = 1 : PtY = 1 : PtDown = 0 : PtWheel = 0
    Case 2                                       ; drawn: go to the point
      If PtRect(name$, @r) = 0
        PtLog$ + "FAIL " + name$ + ": not drawn" + #LF$ : PtFails + 1
        PtFrame = 0 : PtPoint = 0 : PtCase + 1 : ProcedureReturn
      EndIf
      Select PtPoint
        Case 0 : PtX = r\x + 2 : PtY = r\y + 2
        Case 1 : PtX = r\x + r\w - 2 : PtY = r\y + r\h - 2
        Case 2 : PtX = r\x + r\w + 2 : PtY = r\y + r\h - 2
        Case 3 : PtX = r\x + r\w - 2 : PtY = r\y + r\h + 2
      EndSelect
      PtClicked$ = ""
      If Left(name$, 4) = "tab " : RightTab = 99 : EndIf   ; no tab selected: a press shows as the new value
      If name$ = "memory pane" : MemTop = 100 : EndIf      ; a wheel turn over it moves this
    Case 3                                       ; press, or for the pane a wheel turn
      If name$ = "memory pane" : PtWheel = 1 : Else : PtDown = 1 : EndIf
    Case 4 : PtDown = 0 : PtWheel = 0            ; release
    Case 6                                       ; what the press did
      PtRect(name$, @r)
      inside = Bool(PtPoint < 2)
      If Left(name$, 4) = "tab "
        got$ = "tab " + Str(RightTab)
        hit = Bool(got$ = name$)
      ElseIf name$ = "memory pane"
        got$ = "MemTop " + Str(MemTop)
        hit = Bool(MemTop <> 100)
      Else
        got$ = PtClicked$
        If got$ = "" : got$ = "nothing" : EndIf
        hit = Bool(PtClicked$ = name$)
      EndIf
      ok = Bool(hit = inside)
      PtPoints + 1
      PtLog$ + StringField("FAIL|ok", 1 + ok, "|") + "  " + LSet(name$, 12) + " rect (" + StrF(r\x, 1) + "," + StrF(r\y, 1) + " " +
               StrF(r\w, 1) + "x" + StrF(r\h, 1) + ")  point (" + StrF(PtX, 0) + "," + StrF(PtY, 0) + ") " +
               StringField("outside|inside", 1 + inside, "|") + "  read back (" + StrF(Neon_MX, 1) + "," + StrF(Neon_MY, 1) + ")  -> " + got$ + #LF$
      If ok = 0 : PtFails + 1 : EndIf
      If Left(name$, 4) = "tab " : RightTab = 0 : EndIf
      PtPoint + 1 : PtFrame = 0
      If PtPoint = 4 : PtPoint = 0 : PtCase + 1 : EndIf
  EndSelect
EndProcedure

Procedure DrawWindow()
  Protected margin.f = Neon_S(12), sw.f, sh.f, sc.f, px.f, py.f, rx.f, rw.f, y.f, sel.i
  Protected mx.i, my.i, down.b, wh.i
  MeasureWindow()
  ; WindowMouseX/Y are already PHYSICAL in this DPI-aware window (the engine's GlUIChrome.pbi section 5a):
  ; passed as they are - multiplied by the scale they put every click 25% right and down at 125%
  mx = WindowMouseX(Win) : my = WindowMouseY(Win) : down = MouseDown : wh = Wheel
  If PtOn : mx = PtX : my = PtY : down = PtDown : wh = PtWheel : EndIf   ; --pointer-test: the synthetic point, the same path
  Neon_ChromeBeginFrame(mx, my, down, wh, KeyCode, KeyChar, 1.0 / 60.0)
  glBindFramebuffer(#GL_FRAMEBUFFER, 0)
  glDisable_(#GL_SCISSOR_TEST)
  glViewport_(0, 0, PhysW, PhysH)
  glClearColor_(0.03, 0.04, 0.06, 1.0) : glClear_(#GL_COLOR_BUFFER_BIT)
  If FullScreen                            ; only the CoCo's picture, black around it
    glClearColor_(0, 0, 0, 1.0) : glClear_(#GL_COLOR_BUFFER_BIT)
    DrawFullScreen()
    Neon_ChromeEndFrame()
    ProcedureReturn
  EndIf
  ; the CoCo's screen: as large as fits the left 58 %, 4:3
  sc = (PhysW * 0.58 - 2 * margin) / #SCR_W
  If (PhysH - 2 * margin) / #SCR_H < sc : sc = (PhysH - 2 * margin) / #SCR_H : EndIf
  If sc >= 2 : sc = Int(sc) : EndIf        ; whole steps once there is room, else as large as fits
  sw = #SCR_W * sc : sh = #SCR_H * sc : px = margin : py = (PhysH - sh) / 2
  Neon_Box(px - Neon_S(2), py - Neon_S(2), sw + Neon_S(4), sh + Neon_S(4), 0.15, 0.20, 0.30)
  Protected t.q = MicroNow()
  ScreenTextureUpload()
  DrawGLSprite(@ScreenSprite, px, py, 0.0, sc, 1.0, 1.0, 1.0, 1.0, #True, -1, -1, -1, -1, #True)
  PartUs(0) + MicroNow() - t : t = MicroNow()
  rx = px + sw + margin : rw = PhysW - rx - margin
  DrawControls(rx, margin, rw, Neon_S(206))
  PartUs(1) + MicroNow() - t : t = MicroNow()
  y = margin + Neon_S(206) + margin
  DrawRegisters(rx, y, rw, Neon_S(200))
  PartUs(2) + MicroNow() - t : t = MicroNow()
  y + Neon_S(200) + margin
  Neon_Panel(rx, y, rw, PhysH - y - margin, "", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  RightTab = Neon_TabStrip(300, rx + 1, y + 1, rw - 2, Neon_S(28), "Disassembly|Memory|Log|Controls", RightTab)
  Select RightTab
    Case 0 : DrawDisassembly(rx, y + Neon_S(32), rw, PhysH - y - margin - Neon_S(32))
    Case 1 : DrawMemory(rx, y + Neon_S(32), rw, PhysH - y - margin - Neon_S(32))
    Case 3 : DrawControlsTab(rx, y + Neon_S(32), rw, PhysH - y - margin - Neon_S(32))
    Default : DrawLog(rx, y + Neon_S(32), rw, PhysH - y - margin - Neon_S(32))
  EndSelect
  PartUs(3) + MicroNow() - t : t = MicroNow()
  Neon_ChromeEndFrame()
  PartUs(4) + MicroNow() - t
EndProcedure

Procedure SaveWindowShot(path$)
  Protected *px = AllocateMemory(PhysW * PhysH * 4), img.i, x.i, y.i, c.l, *row
  glReadBuffer_(#GL_BACK)
  glReadPixels_(0, 0, PhysW, PhysH, #GL_RGBA, #GL_UNSIGNED_BYTE, *px)
  img = CreateImage(#PB_Any, PhysW, PhysH, 24)
  If img And StartDrawing(ImageOutput(img))
    For y = 0 To PhysH - 1
      *row = *px + (PhysH - 1 - y) * PhysW * 4
      For x = 0 To PhysW - 1
        c = PeekL(*row + x * 4) : Plot(x, y, RGB(c & 255, (c >> 8) & 255, (c >> 16) & 255))
      Next
    Next
    StopDrawing() : SaveImage(img, path$, #PB_ImagePlugin_PNG)
  EndIf
  FreeMemory(*px)
EndProcedure

; ---------------------------------------------------------------- --fullscreen-test
; Full screen by its own keys, no real pointer or keyboard: the keys are posted to the window's GL gadget
; (as the keyboard would send them), ALT and CTRL held through this thread's own keyboard state
; (SetKeyboardState, which no other program reads), and what reached the CoCo read from HostKeyLog$.
; Checked: Esc in the window is BREAK and leaves the window alone; F11 covers the window's monitor, the
; picture is 4:3, as large as fits and centred, the machine runs on at 60 frames a second, End is BREAK
; there, the scale is measured again; Esc leaves without reaching the CoCo, and the window's rectangle and
; style come back exactly; Ctrl and Alt with a letter are the CoCo's CTRL and ALT.
Global FtOn.i, FtFile$, FtShot$, FtStep.i, FtWait.i, FtFails.i, FtLog$, FtRect.RECT, FtStyle.i, FtFrame.i, FtMs.q
Global Dim FtKeys.a(255)

Procedure FtCheck(ok.i, what$)
  If ok = 0 : FtFails + 1 : FtLog$ + "FAIL " : Else : FtLog$ + "ok   " : EndIf
  FtLog$ + what$ + #LF$
EndProcedure
Procedure FtKey(vk.i, sys.i = 0)
  If sys
    PostMessage_(GadgetID(Gl), #WM_SYSKEYDOWN, vk, $20000000) : PostMessage_(GadgetID(Gl), #WM_SYSKEYUP, vk, $E0000000)
  Else
    PostMessage_(GadgetID(Gl), #WM_KEYDOWN, vk, 0) : PostMessage_(GadgetID(Gl), #WM_KEYUP, vk, $C0000000)
  EndIf
EndProcedure
Procedure FtHold(vk.i)   ; 0: nothing held
  Protected i.i
  For i = 0 To 255 : FtKeys(i) = 0 : Next
  If vk : FtKeys(vk) = $80 : EndIf
  SetKeyboardState_(@FtKeys(0))
EndProcedure
Procedure FtSent(want$, what$)
  FtCheck(Bool(HostKeyLog$ = want$), what$ + " (sent to the CoCo: '" + Trim(HostKeyLog$) + "')")
  HostKeyLog$ = ""
EndProcedure

; One step, after each frame is drawn. Returns 1 when done.
Procedure.i FtStep()
  Protected r.RECT, mi.MONITORINFO, hwnd.i = WindowID(Win), rate.f, f.i
  FtWait + 1
  If FtWait < 20 : ProcedureReturn 0 : EndIf   ; frames for each step to settle
  If FtStep = 3 And ElapsedMilliseconds() - FtMs < 1000 : ProcedureReturn 0 : EndIf   ; a second of full screen
  FtWait = 0 : FtStep + 1
  Select FtStep
    Case 1
      GetWindowRect_(hwnd, @FtRect) : FtStyle = GetWindowLongPtr_(hwnd, #GWL_STYLE) : HostKeyLog$ = ""
      FtKey(#VK_ESCAPE)
    Case 2
      FtCheck(Bool(FullScreen = 0), "Esc in the window leaves the window as it is")
      FtSent("27 ", "Esc in the window is BREAK")
      FtKey(#VK_F11)
    Case 3
      FtFrame = CocoFrames : FtMs = ElapsedMilliseconds()
    Case 4
      GetWindowRect_(hwnd, @r) : mi\cbSize = SizeOf(MONITORINFO) : GetMonitorInfo_(MonitorFromWindow_(hwnd, 2), @mi)
      FtCheck(FullScreen, "F11 entered full screen")
      FtCheck(Bool(r\left = mi\rcMonitor\left And r\top = mi\rcMonitor\top And r\right = mi\rcMonitor\right And r\bottom = mi\rcMonitor\bottom),
              "the window covers its monitor (" + Str(r\left) + "," + Str(r\top) + " - " + Str(r\right) + "," + Str(r\bottom) + "; monitor " +
              Str(mi\rcMonitor\left) + "," + Str(mi\rcMonitor\top) + " - " + Str(mi\rcMonitor\right) + "," + Str(mi\rcMonitor\bottom) + ")")
      FtCheck(Bool(PhysW = mi\rcMonitor\right - mi\rcMonitor\left And PhysH = mi\rcMonitor\bottom - mi\rcMonitor\top), "the canvas is the monitor: " + Str(PhysW) + "x" + Str(PhysH))
      FtCheck(Bool(Abs(FsViewW / FsViewH - 4.0 / 3.0) < 0.005), "the picture " + StrF(FsViewW, 0) + "x" + StrF(FsViewH, 0) + " is 4:3 (" + StrF(FsViewW / FsViewH, 4) + ")")
      FtCheck(Bool(FsViewW <= PhysW And FsViewH <= PhysH And (Abs(FsViewW - PhysW) <= 1 Or Abs(FsViewH - PhysH) <= 1)), "as large as fits in " + Str(PhysW) + "x" + Str(PhysH))
      FtCheck(Bool(Abs(FsViewX * 2 + FsViewW - PhysW) <= 1 And Abs(FsViewY * 2 + FsViewH - PhysH) <= 1), "centred at " + StrF(FsViewX, 0) + "," + StrF(FsViewY, 0))
      FtCheck(Bool(Abs(Neon_UIScale - PhysW / Util_WinWidth) < 0.01), "the scale measured again: " + StrF(Neon_UIScale, 3))
      rate = (CocoFrames - FtFrame) * 1000.0 / (ElapsedMilliseconds() - FtMs)
      FtCheck(Bool(Abs(rate - 59.92) < 3), "the machine runs on at its own rate in full screen (" + StrF(rate, 1) + " frames a second, 59.92 wanted)")
      If FtShot$ : SaveWindowShot(FtShot$) : EndIf
      FtKey(#VK_END)
    Case 5
      FtSent("27 ", "End is BREAK in full screen")
      FtCheck(FullScreen, "End leaves full screen alone")
      FtKey(#VK_ESCAPE)
    Case 6
      GetWindowRect_(hwnd, @r)
      FtCheck(Bool(FullScreen = 0), "Esc left full screen")
      FtSent("", "Esc in full screen is not BREAK")
      FtCheck(Bool(r\left = FtRect\left And r\top = FtRect\top And r\right = FtRect\right And r\bottom = FtRect\bottom),
              "the window's rectangle is back (" + Str(r\left) + "," + Str(r\top) + " - " + Str(r\right) + "," + Str(r\bottom) + ")")
      FtCheck(Bool(GetWindowLongPtr_(hwnd, #GWL_STYLE) = FtStyle), "the window's style is back")
      FtCheck(Bool(Abs(Neon_UIScale - PhysW / Util_WinWidth) < 0.01 And PhysW = Round(Util_WinWidth * Neon_UIScale, #PB_Round_Nearest)), "the scale measured again: " + StrF(Neon_UIScale, 3) + ", canvas " + Str(PhysW) + "x" + Str(PhysH))
      FtHold(#VK_CONTROL) : FtKey(#VK_A)
    Case 7
      FtHold(0)
      FtSent("135 65 ", "Ctrl+A is CTRL+A")
      FtHold(#VK_MENU) : FtKey(#VK_A, 1)
    Case 8
      FtHold(0)
      FtSent("134 65 ", "Alt+A is ALT+A")
      FtKey(#VK_F11)
    Case 9
      FtCheck(FullScreen, "F11 again: full screen")
      FtKey(#VK_F11)
    Case 10
      GetWindowRect_(hwnd, @r)
      FtCheck(Bool(FullScreen = 0 And r\left = FtRect\left And r\top = FtRect\top And r\right = FtRect\right And r\bottom = FtRect\bottom), "F11 in full screen leaves it, the rectangle back")
      FtLog$ + "fullscreen-test: " + Str(FtFails) + " failures" + #LF$
      f = CreateFile(#PB_Any, FtFile$)
      If f : WriteString(f, FtLog$) : CloseFile(f) : EndIf
      ProcedureReturn 1
  EndSelect
  ProcedureReturn 0
EndProcedure

Procedure WindowRun()
  Protected ev.i, quit.i, due.q, now.q, n.i
  Gl = OpenGLWindow("Tandy Color Computer 3 - PureBasic desktop", 1400, 820,
                    #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_SizeGadget)
  If Gl = 0 : MessageRequester("CoCo 3", "Could not open an OpenGL window.") : ProcedureReturn : EndIf
  Win = Util_MainWindowID
  ; the engine binds Esc to a shortcut of its own; here Esc is BREAK in the window and leaves full screen
  RemoveKeyboardShortcut(Win, #PB_Shortcut_Escape)
  MeasureWindow()   ; the scale, the fonts, the canvas
  GL_SetVSync(1)
  SetGadgetAttribute(Gl, #PB_OpenGL_SetContext, #True)
  ScreenTextureInit()
  HostSoundOpen()
  SoundStart()
  SetActiveGadget(Gl)
  SpeedMark = ElapsedMilliseconds()
  due = MicroNow()
  Repeat
    Repeat
      ev = WindowEvent()
      Select ev
        Case #PB_Event_CloseWindow : quit = 1
        Case #PB_Event_MoveWindow, #PB_Event_SizeWindow, #PB_Event_MaximizeWindow, #PB_Event_RestoreWindow
          MeasureWindow()   ; resized, or moved to a monitor with another scale: the fonts and Neon_UIScale again
        Case #PB_Event_Gadget
          If EventGadget() = Gl
            Select EventType()
              Case #PB_EventType_LeftButtonDown : MouseDown = #True
              Case #PB_EventType_LeftButtonUp : MouseDown = #False
              Case #PB_EventType_MouseWheel : Wheel + GetGadgetAttribute(Gl, #PB_OpenGL_WheelDelta)
              Case #PB_EventType_KeyDown
                KeyCode = GetGadgetAttribute(Gl, #PB_OpenGL_Key)
                If Neon_FocusID = 0 : HostKeyDown(KeyCode) : EndIf   ; the controls table (controls.pbi)
              Case #PB_EventType_Input
                KeyChar = GetGadgetAttribute(Gl, #PB_OpenGL_Input)
                If Neon_FocusID = 0 And KeyChar >= 32 And KeyChar < 127 : KeyPut(KeyChar) : EndIf
            EndSelect
          EndIf
      EndSelect
    Until ev = 0
    If EmuRunning And EmuStop$ = ""
      now = MicroNow() : n = 0
      If EmuFull
        Repeat : EmuFrame() : n + 1 : Until MicroNow() - now > 15000
        due = MicroNow()
      Else
        While now - due >= 0 And n < 12 : EmuFrame() : n + 1 : due + #FRAME_US : Wend   ; catch up after a slow flip
        If now - due > 200000 : due = now : EndIf
      EndIf
    Else
      due = MicroNow()
    EndIf
    PartUs(5) + MicroNow() - now
    SpeedUpdate()
    now = MicroNow()
    DrawWindow()
    PartUs(6) + MicroNow() - now : PartLoops + 1 : PassFrames + n
    If PartLoops >= 60 And ShowTiming = 0 : For n = 0 To 7 : PartUs(n) = 0 : Next : PartLoops = 0 : EmuCpuUs = 0 : EmuSndUs = 0 : EndIf
    If PartLoops >= 60
      HostOut("ms per pass: screen " + StrF(PartUs(0) / 60000.0, 2) + " controls " + StrF(PartUs(1) / 60000.0, 2) + " regs " + StrF(PartUs(2) / 60000.0, 2) +
              " tab " + StrF(PartUs(3) / 60000.0, 2) + " end " + StrF(PartUs(4) / 60000.0, 2) + " emu " + StrF(PartUs(5) / 60000.0, 2) + " (render " + StrF(PartUs(7) / 60000.0, 2) + " cpu " + StrF(EmuCpuUs / 60000.0, 2) + " sound " + StrF(EmuSndUs / 60000.0, 2) + ") draw " + StrF(PartUs(6) / 60000.0, 2) + " frames in 60 passes " + Str(PassFrames)) : Eol() : PassFrames = 0
      For n = 0 To 7 : PartUs(n) = 0 : Next : PartLoops = 0 : EmuCpuUs = 0 : EmuSndUs = 0
    EndIf
    If ShotPath$ <> "" And EmuFrames >= ShotFrames
      SaveWindowShot(ShotPath$) : quit = 1
      If CreateFile(1, ShotPath$ + ".log") : WriteString(1, HostLog$ + StatusLine() + #LF$) : CloseFile(1) : EndIf
    EndIf
    SetGadgetAttribute(Gl, #PB_OpenGL_FlipBuffers, #True)
    Wheel = 0 : KeyCode = 0 : KeyChar = 0
    If PtOn
      PtStep()
      If PtDone : quit = 1 : EndIf
    EndIf
    If FtOn And FtStep() : quit = 1 : EndIf
  Until quit
  LeaveFullScreen()
  HostSoundClose()
  If PtOn : End PtFails : EndIf   ; --pointer-test: the number of failures
  If FtOn : End FtFails : EndIf   ; --fullscreen-test: the number of failures
EndProcedure

; ---------------------------------------------------------------- start

Define i.i, a$, rom$ = GetPathPart(ProgramFilename()) + "roms\coco3.rom", cart$ = GetPathPart(ProgramFilename()) + "roms\disk11.rom"
Define logFrames.i = -1, err$, d.i
Dim diskArg$(3) : Dim newDisk$(3)
ControlsInit()
For i = 0 To CountProgramParameters() - 1
  a$ = ProgramParameter(i)
  Select LCase(a$)
    Case "--rom" : i + 1 : rom$ = ProgramParameter(i)
    Case "--cart" : i + 1 : cart$ = ProgramParameter(i)
    Case "--no-cart" : cart$ = ""
    Case "--log" : i + 1 : logFrames = Val(ProgramParameter(i))
    Case "--type" : i + 1 : TypeText$ = ProgramParameter(i)
    Case "--type-at" : i + 1 : TypeAt = Val(ProgramParameter(i))
    Case "--type-file"
      i + 1
      If ReadFile(0, ProgramParameter(i))
        While Not Eof(0) : TypeText$ + ReadString(0) + "\n" : Wend
        CloseFile(0)
      EndIf
    Case "--fast" : EmuFull = 1
    Case "--timing" : ShowTiming = 1
    Case "--wav" : i + 1 : HostWav$ = ProgramParameter(i)
    Case "--mute" : HostSndMuted = 1
    Case "--tab" : i + 1 : RightTab = Val(ProgramParameter(i))   ; the right-hand pane: 0 disassembly, 1 memory, 2 log, 3 controls
    Case "--pointer-test" : i + 1 : PtFile$ = ProgramParameter(i) : PtOn = 1 : HostSndMuted = 1 : PtInit()
    Case "--fullscreen-test" : i + 1 : FtFile$ = ProgramParameter(i) : FtOn = 1 : HostSndMuted = 1
      If i + 1 < CountProgramParameters() And Left(ProgramParameter(i + 1), 2) <> "--" : i + 1 : FtShot$ = ProgramParameter(i) : EndIf
    Case "--controls-md"   ; the README's Controls table, from the controls table
      i + 1
      If CreateFile(0, ProgramParameter(i)) : WriteString(0, ControlsMarkdown()) : CloseFile(0) : End 0 : EndIf
      End 1
    Case "--shot" : i + 1 : ShotPath$ = ProgramParameter(i) : i + 1 : ShotFrames = Val(ProgramParameter(i))
    Default
      For d = 0 To 3
        If LCase(a$) = "--disk" + Str(d) : i + 1 : diskArg$(d) = ProgramParameter(i) : EndIf
        If LCase(a$) = "--new-disk" + Str(d) : i + 1 : newDisk$(d) = ProgramParameter(i) : EndIf
      Next
  EndSelect
Next
If logFrames >= 0 : OpenConsole() : HostConsole = 1 : EndIf
VideoInit()
CompilerIf #COCO_CPU = 1
  CpuDisasmInit()
CompilerEndIf
CocoReset()                              ; (maps memory; the ROMs are looked up when the CPU resets)
err$ = HostLoadRoms(rom$, cart$)
If err$ <> ""
  If logFrames >= 0 : PrintN("ERROR: " + err$) : End 1 : EndIf
  MessageRequester("CoCo 3", err$) : End 1
EndIf
For d = 0 To 3
  If newDisk$(d) <> "" : err$ = HostDiskNew(d, newDisk$(d)) : If err$ <> "" : HostOut("drive " + Str(d) + ": " + err$) : Eol() : EndIf : EndIf
  If diskArg$(d) <> "" : err$ = HostDiskMount(d, diskArg$(d)) : If err$ <> "" : HostOut("drive " + Str(d) + ": " + err$) : Eol() : EndIf : EndIf
Next
CocoReset() : CocoCpuReset()
HostOut("CoCo 3 desktop: 512 KB, ROM " + GetFilePart(rom$)) : If cart$ <> "" : HostOut(", cartridge " + GetFilePart(cart$)) : EndIf : Eol()
If logFrames >= 0
  SoundStart()
  ConsoleRun(logFrames)
  End 0
EndIf
WindowRun()
