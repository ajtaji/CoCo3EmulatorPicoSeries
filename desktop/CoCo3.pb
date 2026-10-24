; Tandy Color Computer 3 for the desktop - PureBasic, drawn with the Neon Arcade Display Engine.
; The same machine as the Pico version: src/machine.pmi, video.pmi, keyboard.pmi, sound.pmi, disk.pmi
; and coco3.pmi are compiled here unchanged; the PC gives it 512 KB of RAM and .DSK files for the FD-502.
;
; BUILD (x64, from PowerShell, C back end):
;   & "C:\Program Files\PureBasic\Compilers\pbcompilerc.exe" desktop\CoCo3.pb /EXE build\CoCo3.exe /THREAD /DPIAWARE
;       [/CONSTANT GL_ENGINE_DIR$=C:/path/to/engine/]   (default below)
;       [/CONSTANT COCO_CPU_DIR$=C:/path/to/6809EmulatorPicoSeries/desktop/]   (default: beside this repo)
; RUN:
;   CoCo3.exe [--rom coco3.rom] [--cart disk11.rom|--no-cart] [--disk0 file.dsk ... --disk3] [--new-disk0 file.dsk]
;       the window. The ROMs default to C:\PMFBuild\coco_roms_build (tools/build_roms.ps1 makes them).
;   CoCo3.exe ... --log N [--type "text"] [--fast]   no window: N frames, a status line a second, the
;       screen as text at the end (--type types into the CoCo after boot, \n for ENTER).
;   CoCo3.exe ... --shot file.png N [--type "text"]  the window for N frames, then its picture, then exit.
; KEYS: typing goes to the CoCo keyboard (arrows, Esc = BREAK, Home = CLEAR, F1, F2); F5 run/pause,
;   F10 one instruction, F11 one frame, F3 reset, F8 full speed, F9 mute.
; The ROMs are Tandy's: none are in the repository.

EnableExplicit

CompilerIf Not Defined(GL_ENGINE_DIR$, #PB_Constant)
  #GL_ENGINE_DIR$ = "C:/Users/ajtaj/Desktop/Neon-Arcade-Dispay-Engine/"
CompilerEndIf
XIncludeFile #GL_ENGINE_DIR$ + "GlTypes.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUtilities.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlMath.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlSpriteFunctions.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUI.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUIChrome.pbi"
UsePNGImageEncoder()

; The log (host.pbi): Say takes a string here; on a Pico it takes a string's address (say_decl.pmi).
Declare HostOut(t$)
Declare Num(v.i)
Declare Eol()
Macro Say(t)
  HostOut(t)
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
  XIncludeFile #COCO_CPU_DIR$ + "cpu6809.pbi"
  XIncludeFile "../src/cpu6809_glue.pmi"
CompilerElse
  XIncludeFile "../src/cpu_none.pmi"
CompilerEndIf
XIncludeFile "../src/machine.pmi"
XIncludeFile "../src/video.pmi"
XIncludeFile "../src/keyboard.pmi"
XIncludeFile "../src/sound.pmi"
XIncludeFile "../src/disk.pmi"
XIncludeFile "../src/coco3.pmi"
XIncludeFile "host.pbi"

#SCR_W = 640
#SCR_H = 480                             ; 240 lines, each shown twice (4:3)
#FRAME_US = 16688                        ; 262 x 1824 GIME clocks at 28.636363 MHz

Global Dim ScrPix.l(#SCR_W * #SCR_H)     ; RGBA, bottom row first (as the engine samples it)
Global EmuRunning.i = 1, EmuFull.i, EmuFrames.q, EmuStop$
Global SpeedMark.q, SpeedCycles.q, SpeedFrames.q, SpeedKhz.f, SpeedFps.f, SpeedX.f
Global TypeText$, TypeAt.i = 240

Procedure.s H2(v.i) : ProcedureReturn RSet(Hex(v & $FF), 2, "0") : EndProcedure
Procedure.s H4(v.i) : ProcedureReturn RSet(Hex(v & $FFFF), 4, "0") : EndProcedure

; The 240 lines of the picture into ScrPix (each line twice).
Procedure ScreenRender()
  Protected line.i, x.i, c.l, *row, *row2
  For line = 0 To 239
    VideoRenderSamples(line)
    *row = @ScrPix((#SCR_H - 1 - line * 2) * #SCR_W)
    *row2 = *row - #SCR_W * 4
    For x = 0 To 639
      c = VideoRgb(VideoSamples(x))
      c = $FF000000 | ((c & $FF) << 16) | (c & $FF00) | ((c >> 16) & $FF)
      PokeL(*row + x * 4, c) : PokeL(*row2 + x * 4, c)
    Next
  Next
EndProcedure

; Keys typed by --type (after the boot screen has come up).
Procedure TypeFeed()
  Protected i.i, c.i
  If TypeText$ = "" Or EmuFrames < TypeAt : ProcedureReturn : EndIf
  For i = 1 To Len(TypeText$)
    c = Asc(Mid(TypeText$, i, 1))
    If c = '\' And Mid(TypeText$, i + 1, 1) = "n" : c = 13 : i + 1 : EndIf
    KeyPut(c)
  Next
  TypeText$ = ""
EndProcedure

Procedure EmuFrame()
  CocoFrame()
  KeyFrame()
  EmuFrames + 1
  TypeFeed()
  HostSoundPump()
  CompilerIf #COCO_CPU = 1
    If CpuStopped And EmuStop$ = "" : EmuStop$ = "6809 stopped: opcode $" + Hex(CpuBadOpcode) + " at $" + H4(CpuPC) : EndIf
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
         StrF(CpuCycles / 1000.0 / (ElapsedMilliseconds() - t0 + 1), 0) + " kHz = " +
         StrF(CpuCycles / 894.886 / (ElapsedMilliseconds() - t0 + 1), 2) + "x a real CoCo 3 at 0.89 MHz")
  CocoTextDump()
EndProcedure

; ---------------------------------------------------------------- the window

Global Win.i, Gl.i, UiScale.f, ScreenTex.l, ScreenSprite.GLSprite
Global MouseDown.b, Wheel.i, KeyCode.i, KeyChar.i, PhysW.i, PhysH.i, RightTab.i, MemTop.i
Global ShotPath$, ShotFrames.i, GetDpiForWindow_.i, QpcFreq.q

Procedure.q MicroNow()
  Protected c.q
  If QpcFreq = 0 : QueryPerformanceFrequency_(@QpcFreq) : EndIf
  QueryPerformanceCounter_(@c)
  ProcedureReturn c * 1000000 / QpcFreq
EndProcedure

Procedure.f WindowScale(w.i)
  Protected dpi.i, lib.i
  If GetDpiForWindow_ = 0
    lib = OpenLibrary(#PB_Any, "user32.dll")
    If lib : GetDpiForWindow_ = GetFunction(lib, "GetDpiForWindow") : EndIf
  EndIf
  If GetDpiForWindow_ : dpi = CallFunctionFast(GetDpiForWindow_, WindowID(w)) : EndIf
  If dpi <= 0 : ProcedureReturn 1.0 : EndIf
  ProcedureReturn dpi / 96.0
EndProcedure

Procedure BuildFonts()
  Protected s.f = UiScale
  *Neon_FontUI = Neon_CreateFontPx("Segoe UI", Round(14 * s, #PB_Round_Nearest))
  *Neon_FontSmall = Neon_CreateFontPx("Segoe UI", Round(12 * s, #PB_Round_Nearest))
  *Neon_FontBold = Neon_CreateFontPx("Segoe UI", Round(15 * s, #PB_Round_Nearest), #PB_Font_Bold)
  *Neon_FontMono = Neon_CreateFontPx("Consolas", Round(13 * s, #PB_Round_Nearest))
  GLFontSetSnapToPixel(*Neon_FontUI, #True) : GLFontSetSnapToPixel(*Neon_FontSmall, #True)
  GLFontSetSnapToPixel(*Neon_FontBold, #True) : GLFontSetSnapToPixel(*Neon_FontMono, #True)
  Neon_UIScale = s
EndProcedure

Procedure SizeGlobals()
  PhysW = GadgetWidth(Gl) * UiScale : PhysH = GadgetHeight(Gl) * UiScale
  Util_BaseWidth = PhysW : Util_BaseHeight = PhysH
  GL_ViewportX = 0 : GL_ViewportY = 0 : GL_ViewportW = PhysW : GL_ViewportH = PhysH
EndProcedure

Procedure ScreenTextureInit()
  glGenTextures_(1, @ScreenTex)
  glBindTexture_(#GL_TEXTURE_2D, ScreenTex)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MIN_FILTER, #GL_LINEAR)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MAG_FILTER, #GL_NEAREST)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_S, #GL_CLAMP_TO_EDGE)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_T, #GL_CLAMP_TO_EDGE)
  glTexImage2D_(#GL_TEXTURE_2D, 0, #GL_RGBA, #SCR_W, #SCR_H, 0, #GL_RGBA, #GL_UNSIGNED_BYTE, @ScrPix(0))
  ScreenSprite\TextureID = ScreenTex : ScreenSprite\Width = #SCR_W : ScreenSprite\Height = #SCR_H
EndProcedure

Procedure ScreenTextureUpload()
  ScreenRender()
  glBindTexture_(#GL_TEXTURE_2D, ScreenTex)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, #SCR_W, #SCR_H, #GL_RGBA, #GL_UNSIGNED_BYTE, @ScrPix(0))
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
  Protected s.f = UiScale, lh.f = GLFontLineHeight(*Neon_FontMono) + 2 * s, ty.f = y + Neon_S(34), tx.f = x + 12 * s, i.i, m$
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
  Protected s.f = UiScale, lh.f = GLFontLineHeight(*Neon_FontMono) + 2 * s, ty.f = y + 6 * s, rows.i, r.i, k.i, a.i, v.i, line$, asc$
  rows = (h - 12 * s) / lh
  If Neon_Hit(x, y, w, h) And Neon_Wheel : MemTop - Neon_Wheel * 3 : EndIf
  If MemTop < 0 : MemTop = 0 : EndIf
  If MemTop > 4096 - rows : MemTop = 4096 - rows : EndIf
  For r = 0 To rows - 1
    a = (MemTop + r) * 16 : line$ = H4(a) + "  " : asc$ = ""
    For k = 0 To 15
      v = CpuPeek(a + k)
      If v < 0 : line$ + "-- " : asc$ + " " : Else : line$ + H2(v) + " " : If v >= 32 And v < 127 : asc$ + Chr(v) : Else : asc$ + "." : EndIf : EndIf
    Next
    Neon_Text(*Neon_FontMono, x + 10 * s, ty, line$ + " " + asc$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Next
EndProcedure

Procedure DrawLog(x.f, y.f, w.f, h.f)
  Protected s.f = UiScale, lh.f = GLFontLineHeight(*Neon_FontMono) + 2 * s, ty.f, n.i, i.i, rows.i
  rows = (h - 12 * s) / lh
  n = CountString(HostLog$, #LF$)
  ty = y + 6 * s
  For i = n - rows + 1 To n
    If i >= 1 : Neon_Text(*Neon_FontMono, x + 10 * s, ty, StringField(HostLog$, i, #LF$), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB) : EndIf
    ty + lh
  Next
EndProcedure

Procedure DrawControls(x.f, y.f, w.f, h.f)
  Protected s.f = UiScale, bx.f = x + 12 * s, by.f = y + Neon_S(36), bh.f = 28 * s, d.i, p$, r$
  Neon_Panel(x, y, w, h, "Tandy Color Computer 3 - 512 KB, Disk BASIC", Neon_C_VioR, Neon_C_VioG, Neon_C_VioB, Neon_S(26))
  If Neon_Button(bx, by, 74 * s, bh, "Run", EmuRunning, Bool(EmuRunning = 0)) : EmuRunning = 1 : EndIf : bx + 80 * s
  If Neon_Button(bx, by, 74 * s, bh, "Pause", #False, EmuRunning) : EmuRunning = 0 : EndIf : bx + 80 * s
  If Neon_Button(bx, by, 74 * s, bh, "Frame", #False, Bool(EmuRunning = 0)) : EmuFrame() : EndIf : bx + 80 * s
  If Neon_Button(bx, by, 74 * s, bh, "Reset") : CocoReset() : CocoCpuReset() : EndIf : bx + 80 * s
  If Neon_Button(bx, by, 96 * s, bh, "Full speed", EmuFull) : EmuFull ! 1 : EndIf : bx + 102 * s
  If Neon_Button(bx, by, 74 * s, bh, "Mute", HostSndMuted) : HostSndMuted ! 1 : EndIf
  by + bh + 8 * s : bx = x + 12 * s
  For d = 0 To 1
    If Neon_Button(bx, by, 110 * s, bh, "Drive " + Str(d) + "...")
      p$ = OpenFileRequester("Disk for drive " + Str(d), "", "CoCo disks (*.dsk)|*.dsk|All files|*.*", 0)
      If p$ <> "" : r$ = HostDiskMount(d, p$) : If r$ <> "" : HostOut(r$) : Eol() : EndIf : EndIf
    EndIf
    Neon_Text(*Neon_FontSmall, bx + 116 * s, by + 7 * s, GetFilePart(HostDiskPath$(d)), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
    bx + w / 2 - 6 * s
  Next
  by + bh + 10 * s
  Neon_Text(*Neon_FontUI, x + 12 * s, by, StatusLine(), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  If EmuStop$ <> "" : Neon_Text(*Neon_FontUI, x + 12 * s, by + 20 * s, EmuStop$, Neon_C_RedR, Neon_C_RedG, Neon_C_RedB) : EndIf
EndProcedure

Procedure DrawWindow()
  Protected margin.f = Neon_S(12), sw.f, sh.f, sc.f, px.f, py.f, rx.f, rw.f, y.f, sel.i
  SizeGlobals()
  Neon_ChromeBeginFrame(WindowMouseX(Win) * UiScale, WindowMouseY(Win) * UiScale, MouseDown, Wheel, KeyCode, KeyChar, 1.0 / 60.0)
  glBindFramebuffer(#GL_FRAMEBUFFER, 0)
  glDisable_(#GL_SCISSOR_TEST)
  glViewport_(0, 0, PhysW, PhysH)
  glClearColor_(0.03, 0.04, 0.06, 1.0) : glClear_(#GL_COLOR_BUFFER_BIT)
  ; the CoCo's screen: as large as fits the left 58 %, 4:3
  sc = (PhysW * 0.58 - 2 * margin) / #SCR_W
  If (PhysH - 2 * margin) / #SCR_H < sc : sc = (PhysH - 2 * margin) / #SCR_H : EndIf
  If sc >= 1 : sc = Int(sc) : EndIf
  sw = #SCR_W * sc : sh = #SCR_H * sc : px = margin : py = (PhysH - sh) / 2
  Neon_Box(px - 2, py - 2, sw + 4, sh + 4, 0.15, 0.20, 0.30)
  ScreenTextureUpload()
  DrawGLSprite(@ScreenSprite, px, py, 0.0, sc, 1.0, 1.0, 1.0, 1.0, #True, -1, -1, -1, -1, #True)
  rx = px + sw + margin : rw = PhysW - rx - margin
  DrawControls(rx, margin, rw, Neon_S(170))
  y = margin + Neon_S(170) + margin
  DrawRegisters(rx, y, rw, Neon_S(250))
  y + Neon_S(250) + margin
  Neon_Panel(rx, y, rw, PhysH - y - margin, "", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  RightTab = Neon_TabStrip(300, rx + 1, y + 1, rw - 2, Neon_S(28), "Log|Memory", RightTab)
  If RightTab = 0
    DrawLog(rx, y + Neon_S(32), rw, PhysH - y - margin - Neon_S(32))
  Else
    DrawMemory(rx, y + Neon_S(32), rw, PhysH - y - margin - Neon_S(32))
  EndIf
  Neon_ChromeEndFrame()
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

; A key the PC sends as a key code, not a character: the CoCo's special keys.
Procedure HostSpecialKey(k.i)
  Select k
    Case #PB_Shortcut_Up : KeyPut($80)
    Case #PB_Shortcut_Down : KeyPut($81)
    Case #PB_Shortcut_Left : KeyPut($82)
    Case #PB_Shortcut_Right : KeyPut($83)
    Case #PB_Shortcut_F1 : KeyPut($84)
    Case #PB_Shortcut_F2 : KeyPut($85)
    Case #PB_Shortcut_Escape : KeyPut(27)
    Case #PB_Shortcut_Home : KeyPut(12)
    Case #PB_Shortcut_Return : KeyPut(13)
    Case #PB_Shortcut_Back : KeyPut(8)
  EndSelect
EndProcedure

Procedure WindowRun()
  Protected ev.i, quit.i, due.q, now.q, n.i
  Gl = OpenGLWindow("Tandy Color Computer 3 - PureBasic desktop", 1400, 820,
                    #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_SizeGadget)
  If Gl = 0 : MessageRequester("CoCo 3", "Could not open an OpenGL window.") : ProcedureReturn : EndIf
  Win = Util_MainWindowID
  UiScale = WindowScale(Win) : BuildFonts()
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
        Case #PB_Event_Gadget
          If EventGadget() = Gl
            Select EventType()
              Case #PB_EventType_LeftButtonDown : MouseDown = #True
              Case #PB_EventType_LeftButtonUp : MouseDown = #False
              Case #PB_EventType_MouseWheel : Wheel + GetGadgetAttribute(Gl, #PB_OpenGL_WheelDelta)
              Case #PB_EventType_KeyDown
                KeyCode = GetGadgetAttribute(Gl, #PB_OpenGL_Key)
                If Neon_FocusID = 0
                  Select KeyCode
                    Case #PB_Shortcut_F5 : EmuRunning ! 1
                    Case #PB_Shortcut_F11 : If EmuRunning = 0 : EmuFrame() : EndIf
                    Case #PB_Shortcut_F3 : CocoReset() : CocoCpuReset()
                    Case #PB_Shortcut_F8 : EmuFull ! 1
                    Case #PB_Shortcut_F9 : HostSndMuted ! 1
                    Default : HostSpecialKey(KeyCode)
                  EndSelect
                EndIf
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
        While now - due >= 0 And n < 4 : EmuFrame() : n + 1 : due + #FRAME_US : Wend
        If now - due > 200000 : due = now : EndIf
      EndIf
    Else
      due = MicroNow()
    EndIf
    SpeedUpdate()
    DrawWindow()
    If ShotPath$ <> "" And EmuFrames >= ShotFrames : SaveWindowShot(ShotPath$) : quit = 1 : EndIf
    SetGadgetAttribute(Gl, #PB_OpenGL_FlipBuffers, #True)
    Wheel = 0 : KeyCode = 0 : KeyChar = 0
  Until quit
  HostSoundClose()
EndProcedure

; ---------------------------------------------------------------- start

Define i.i, a$, rom$ = "C:\PMFBuild\coco_roms_build\coco3.rom", cart$ = "C:\PMFBuild\coco_roms_build\disk11.rom"
Define logFrames.i = -1, err$, d.i
Dim diskArg$(3) : Dim newDisk$(3)
For i = 0 To CountProgramParameters() - 1
  a$ = ProgramParameter(i)
  Select LCase(a$)
    Case "--rom" : i + 1 : rom$ = ProgramParameter(i)
    Case "--cart" : i + 1 : cart$ = ProgramParameter(i)
    Case "--no-cart" : cart$ = ""
    Case "--log" : i + 1 : logFrames = Val(ProgramParameter(i))
    Case "--type" : i + 1 : TypeText$ = ProgramParameter(i)
    Case "--type-at" : i + 1 : TypeAt = Val(ProgramParameter(i))
    Case "--fast" : EmuFull = 1
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
