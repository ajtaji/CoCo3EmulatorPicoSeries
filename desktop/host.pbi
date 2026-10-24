; The PC as the CoCo 3's host: what src/*.pmi asks of a board (the log, the screen text, a line hook,
; disk sectors kept in .DSK files, sound to the speakers), for desktop/CoCo3.pb.

; ---------------------------------------------------------------- the log (console and the window)

Global HostLog$, HostLine$, HostConsole.i
Procedure HostOut(t$)
  HostLine$ + t$
EndProcedure
Procedure Num(v.i)
  HostOut(Str(v))
EndProcedure
Procedure Eol()
  If HostConsole : PrintN(HostLine$) : EndIf
  HostLog$ + HostLine$ + #LF$
  If Len(HostLog$) > 20000 : HostLog$ = Right(HostLog$, 16000) : EndIf
  HostLine$ = ""
EndProcedure
Procedure CocoPutc(c.i)
  HostOut(Chr(c))
EndProcedure

Procedure VideoSendRow(y.i, pixels.i)    ; the panel's (video.pmi's VideoFrame); the PC draws through ScreenRender
EndProcedure
Procedure CocoLineHook()
EndProcedure
Procedure CocoBoardSetup()
EndProcedure
Procedure CocoFrameHook()
EndProcedure
Procedure CocoBoardService()
EndProcedure
Procedure CocoParkVideo(on.i)
EndProcedure

; ---------------------------------------------------------------- disks: .DSK files

Global Dim HostDiskPath$(#DISK_SLOTS)
Global Dim *HostDiskMem(#DISK_SLOTS)
Global Dim HostDiskBytes.i(#DISK_SLOTS)

; Put a .DSK (JVC) file in drive d. Returns "" or what is wrong with it.
Procedure.s HostDiskMount(d.i, path$)
  Protected f.i, n.i, head.i, body.i, sides.i
  If d < 0 Or d >= #DISK_SLOTS : ProcedureReturn "there are drives 0-3" : EndIf
  f = ReadFile(#PB_Any, path$)
  If f = 0 : ProcedureReturn "cannot open " + path$ : EndIf
  n = Lof(f)
  head = n % 256 : body = n - head : sides = 1
  If body <= 0 Or body % (18 * 256) : CloseFile(f) : ProcedureReturn path$ + " is not a whole number of 18-sector tracks" : EndIf
  If *HostDiskMem(d) : FreeMemory(*HostDiskMem(d)) : EndIf
  *HostDiskMem(d) = AllocateMemory(n)
  ReadData(f, *HostDiskMem(d), n) : CloseFile(f)
  If head >= 2 And PeekA(*HostDiskMem(d) + 1) = 2 : sides = 2 : EndIf
  HostDiskPath$(d) = path$ : HostDiskBytes(d) = n
  DiskBase(d) = *HostDiskMem(d) + head : DiskFlash(d) = head
  DiskSides(d) = sides : DiskSpt(d) = 18 : DiskTracks(d) = body / (18 * 256 * sides) : DiskHead(d) = 0
  ProcedureReturn ""
EndProcedure

; A new blank 35-track disk file (every byte $FF: an empty Disk BASIC directory), then mounted.
Procedure.s HostDiskNew(d.i, path$)
  Protected f.i, *m = AllocateMemory(35 * 18 * 256)
  FillMemory(*m, 35 * 18 * 256, $FF)
  f = CreateFile(#PB_Any, path$)
  If f = 0 : FreeMemory(*m) : ProcedureReturn "cannot create " + path$ : EndIf
  WriteData(f, *m, 35 * 18 * 256) : CloseFile(f) : FreeMemory(*m)
  ProcedureReturn HostDiskMount(d, path$)
EndProcedure

; disk.pmi's DiskStore: the sector into memory and into the file at once.
Procedure.i DiskStore(d.i, off.i, src.i)
  Protected f.i
  If *HostDiskMem(d) = 0 : ProcedureReturn 0 : EndIf
  CopyMemory(src, DiskBase(d) + off, 256)
  f = OpenFile(#PB_Any, HostDiskPath$(d))
  If f = 0 : ProcedureReturn 0 : EndIf
  FileSeek(f, DiskFlash(d) + off) : WriteData(f, src, 256) : CloseFile(f)
  ProcedureReturn 1
EndProcedure

; ---------------------------------------------------------------- the ROMs, from files

Global *HostRom, *HostCart
; coco3.rom (32 KB) and, optionally, a cartridge (Disk BASIC, 8 or 16 KB). Returns "" or the problem.
Procedure.s HostLoadRoms(rom$, cart$)
  Protected f.i, n.i
  f = ReadFile(#PB_Any, rom$)
  If f = 0 : ProcedureReturn "cannot open the CoCo 3 ROM " + rom$ + " (build it with tools/build_roms.ps1)" : EndIf
  If Lof(f) <> 32768 : CloseFile(f) : ProcedureReturn rom$ + " is not a 32 KB CoCo 3 ROM" : EndIf
  *HostRom = AllocateMemory(32768) : ReadData(f, *HostRom, 32768) : CloseFile(f)
  CocoRom = *HostRom
  VideoLoadFont(CocoRom, $709D)
  CocoCart = 0 : CocoCartBytes = 0
  If cart$ <> ""
    f = ReadFile(#PB_Any, cart$)
    If f = 0 : ProcedureReturn "cannot open the cartridge ROM " + cart$ : EndIf
    n = Lof(f)
    If n <> 8192 And n <> 16384 : CloseFile(f) : ProcedureReturn cart$ + " is not an 8 or 16 KB cartridge ROM" : EndIf
    *HostCart = AllocateMemory(n) : ReadData(f, *HostCart, n) : CloseFile(f)
    CocoCart = *HostCart : CocoCartBytes = n
  EndIf
  ProcedureReturn ""
EndProcedure

; ---------------------------------------------------------------- sound: waveOut, 48 kHz mono

#HOST_SND_BUFFERS = 8
#HOST_SND_SAMPLES = 800                  ; one 60 Hz frame
Global HostSndDevice.i, HostSndOpen.i, HostSndRead.i, HostSndMuted.i, HostSndUnderruns.i
Global Dim HostSndHeader.WAVEHDR(#HOST_SND_BUFFERS - 1)
Global Dim *HostSndBuf(#HOST_SND_BUFFERS - 1)
Global CocoAudioLive.i

Procedure.i CocoAudioOn()
  ProcedureReturn CocoAudioLive
EndProcedure
Procedure CocoAudioReport()
EndProcedure
Procedure CocoAudioPoll()
EndProcedure

Procedure.i HostSoundOpen()
  Protected fmt.WAVEFORMATEX, i.i
  fmt\wFormatTag = #WAVE_FORMAT_PCM : fmt\nChannels = 1 : fmt\nSamplesPerSec = 48000
  fmt\wBitsPerSample = 16 : fmt\nBlockAlign = 2 : fmt\nAvgBytesPerSec = 96000
  If waveOutOpen_(@HostSndDevice, #WAVE_MAPPER, @fmt, 0, 0, #CALLBACK_NULL) <> #MMSYSERR_NOERROR : ProcedureReturn 0 : EndIf
  For i = 0 To #HOST_SND_BUFFERS - 1
    *HostSndBuf(i) = AllocateMemory(#HOST_SND_SAMPLES * 2)
    HostSndHeader(i)\lpData = *HostSndBuf(i)
    HostSndHeader(i)\dwBufferLength = #HOST_SND_SAMPLES * 2
    waveOutPrepareHeader_(HostSndDevice, @HostSndHeader(i), SizeOf(WAVEHDR))
    HostSndHeader(i)\dwFlags | #WHDR_DONE
  Next
  HostSndOpen = 1 : CocoAudioLive = 1
  ProcedureReturn 1
EndProcedure

; The sound thread: hands the device each whole buffer of new samples as the machine makes them. waveOut
; calls block for milliseconds at a time (24 ms a window pass, measured), so they are kept off the thread
; that runs the machine and draws the window.
Global HostSndThread.i, HostSndQuit.i
Procedure HostSoundThread(*unused)
  Protected i.i, k.i, *b, pending.i, wrote.i
  While HostSndQuit = 0
    wrote = 0
    If SoundSamples - HostSndRead > #SOUND_RING - #HOST_SND_SAMPLES : HostSndRead = SoundSamples - #HOST_SND_SAMPLES : EndIf
    If SoundSamples - HostSndRead >= #HOST_SND_SAMPLES
      pending = 0
      For i = 0 To #HOST_SND_BUFFERS - 1
        If (HostSndHeader(i)\dwFlags & #WHDR_DONE) = 0 : pending + 1 : EndIf
      Next
      For i = 0 To #HOST_SND_BUFFERS - 1
        If HostSndHeader(i)\dwFlags & #WHDR_DONE
          If pending = 0 : HostSndUnderruns + 1 : EndIf
          *b = *HostSndBuf(i)
          For k = 0 To #HOST_SND_SAMPLES - 1
            If HostSndMuted
              PokeW(*b + k * 2, 0)
            Else
              PokeW(*b + k * 2, SoundRing((HostSndRead + k) & (#SOUND_RING - 1)))
            EndIf
          Next
          HostSndHeader(i)\dwFlags & ~#WHDR_DONE
          waveOutWrite_(HostSndDevice, @HostSndHeader(i), SizeOf(WAVEHDR))
          wrote = 1
          Break
        EndIf
      Next
      HostSndRead + #HOST_SND_SAMPLES        ; (dropped when every buffer is queued: the machine is ahead)
    EndIf
    If wrote = 0 : Delay(2) : EndIf
  Wend
EndProcedure

Procedure HostSoundPump()
  If HostSndOpen And HostSndThread = 0 : HostSndThread = CreateThread(@HostSoundThread(), 0) : EndIf
  If HostSndOpen = 0 : HostSndRead = SoundSamples : EndIf
EndProcedure

Procedure HostSoundClose()
  If HostSndThread : HostSndQuit = 1 : WaitThread(HostSndThread, 1000) : HostSndThread = 0 : EndIf
  If HostSndOpen : waveOutReset_(HostSndDevice) : waveOutClose_(HostSndDevice) : HostSndOpen = 0 : EndIf
EndProcedure
