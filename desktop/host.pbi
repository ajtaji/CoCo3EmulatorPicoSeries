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

Procedure VideoSendDone()
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
Global HostSndSkips.i, HostSndOverruns.i, HostWav$, HostWavFile.i, HostWavBytes.i, HostSndEvents$

Procedure.i CocoAudioOn()
  ProcedureReturn CocoAudioLive
EndProcedure
Procedure CocoAudioReport()
EndProcedure
Procedure CocoAudioPoll()
EndProcedure

; --wav file: what the device was given, as a 48 kHz mono WAV, and file.txt: where the stream broke.
Procedure HostWavHeader(f.i, bytes.i)
  FileSeek(f, 0)
  WriteLong(f, $46464952) : WriteLong(f, 36 + bytes) : WriteLong(f, $45564157) : WriteLong(f, $20746D66)
  WriteLong(f, 16) : WriteWord(f, 1) : WriteWord(f, 1) : WriteLong(f, 48000) : WriteLong(f, 96000)
  WriteWord(f, 2) : WriteWord(f, 16) : WriteLong(f, $61746164) : WriteLong(f, bytes)
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
  If HostWav$ <> ""
    HostWavFile = CreateFile(#PB_Any, HostWav$)
    If HostWavFile : HostWavHeader(HostWavFile, 0) : EndIf
  EndIf
  HostSndOpen = 1 : CocoAudioLive = 1
  ProcedureReturn 1
EndProcedure

; The sound thread. The machine makes 48,000 samples a second by the PC's timer; the sound device plays
; 48,000 by its own clock, and the two differ (measured: the machine ran 0.13% ahead of the Bluetooth
; speaker, so the backlog grew until the old reader jumped 449 samples forward every 7.25 s - a click).
; So the reader follows the device: it reads the machine's samples at a step a fraction of a percent
; above or below one, to keep about #HOST_SND_TARGET samples between the machine and the speaker. A step
; of 1.003 moves a 36-sample half period by 0.1 sample: nothing to hear. waveOut calls block for
; milliseconds at a time (24 ms a window pass, measured), so they are kept off the machine's thread, and
; the machine's 2048-sample ring is copied into a FIFO of its own once a frame (HostSoundPump), which a
; blocked thread cannot overrun.
#HOST_SND_FIFO = 65536                   ; samples, a power of two (1.4 s)
#HOST_SND_TARGET = 4000                  ; samples queued or waiting (83 ms)
#HOST_SND_LIMIT = 24000                  ; beyond this (the machine ran fast or was held) skip ahead
Global Dim HostSndFifo.w(#HOST_SND_FIFO)
Global HostFifoW.i, HostFifoR.q          ; HostFifoR: 32.16 fixed point
Global HostSndThread.i, HostSndQuit.i, HostSndLast.i, HostSndStep.i = 65536, HostSndHeld.i, HostSndWrites.i, HostSndLatency.i = #HOST_SND_TARGET * 16, HostPumpAt.q, HostPumpGaps$, HostThreadAt.q
Procedure HostSoundThread(*unused)
  Protected i.i, k.i, *b, pending.i, free.i, backlog.i, latency.i, pos.q, v.i
  While HostSndQuit = 0
    If HostWav$ <> "" And HostThreadAt And ElapsedMilliseconds() - HostThreadAt > 30 : HostSndEvents$ + "sound thread gap " + Str(ElapsedMilliseconds() - HostThreadAt) + " ms at " + Str(HostWavBytes / 2) + #LF$ : EndIf
    HostThreadAt = ElapsedMilliseconds()
    pending = 0 : free = -1
    For i = 0 To #HOST_SND_BUFFERS - 1
      If HostSndHeader(i)\dwFlags & #WHDR_DONE
        If free < 0 : free = i : EndIf
      Else
        pending + 1
      EndIf
    Next
    backlog = HostFifoW - (HostFifoR >> 16)
    If backlog > #HOST_SND_LIMIT
      HostSndSkips + 1 : HostSndEvents$ + "skip " + Str(backlog - #HOST_SND_TARGET) + " at " + Str(HostWavBytes / 2) + #LF$
      HostFifoR = (HostFifoW - #HOST_SND_TARGET) << 16
      backlog = #HOST_SND_TARGET
    EndIf
    ; a buffer goes out when the machine has made it, or - so the speaker never falls silent with a jump
    ; to 0 - holding the last level when the device is about to run dry (the machine paused or slow)
    If free >= 0 And (backlog >= #HOST_SND_SAMPLES + 16 Or pending <= 1)
      latency = backlog + pending * #HOST_SND_SAMPLES
      HostSndLatency = HostSndLatency + latency - HostSndLatency / 16       ; (x16: averaged over 16 buffers)
      HostSndStep = 65536 + (HostSndLatency / 16 - #HOST_SND_TARGET) / 8
      If HostSndStep > 65536 + 330 : HostSndStep = 65536 + 330 : EndIf      ; +0.5%
      If HostSndStep < 65536 - 330 : HostSndStep = 65536 - 330 : EndIf      ; -0.5%
      If pending = 0 And HostWavBytes : HostSndUnderruns + 1 : HostSndEvents$ + "underrun at " + Str(HostWavBytes / 2) + #LF$ : EndIf
      *b = *HostSndBuf(free)
      pos = HostFifoR
      For k = 0 To #HOST_SND_SAMPLES - 1
        If (pos >> 16) < HostFifoW
          v = HostSndFifo((pos >> 16) & (#HOST_SND_FIFO - 1)) : pos + HostSndStep
        Else
          v = HostSndLast : HostSndHeld + 1  ; (ran dry: hold, and read on from here when it comes)
        EndIf
        PokeW(*b + k * 2, v) : HostSndLast = v
      Next
      HostFifoR = pos
      HostSndWrites + 1
      If HostWav$ <> "" And HostSndWrites % 20 = 0
        HostSndEvents$ + "w " + Str(HostSndWrites) + " pending " + Str(pending) + " backlog " + Str(backlog) + " step " + Str(HostSndStep - 65536) + " held " + Str(HostSndHeld) + #LF$
      EndIf
      If HostWavFile : WriteData(HostWavFile, *b, #HOST_SND_SAMPLES * 2) : EndIf
      If HostSndMuted : FillMemory(*b, #HOST_SND_SAMPLES * 2, 0) : EndIf
      HostSndHeader(free)\dwFlags & ~#WHDR_DONE
      waveOutWrite_(HostSndDevice, @HostSndHeader(free), SizeOf(WAVEHDR))
      HostWavBytes + #HOST_SND_SAMPLES * 2
    Else
      Delay(2)
    EndIf
  Wend
EndProcedure

; Once a frame, on the machine's thread: the ring's new samples into the FIFO.
Procedure HostSoundPump()
  Protected n.i, now.q = ElapsedMilliseconds()
  If HostSndOpen = 0 : HostSndRead = SoundSamples : ProcedureReturn : EndIf
  If HostWav$ <> "" And HostPumpAt And now - HostPumpAt > 50 : HostPumpGaps$ + Str(now - HostPumpAt) + " ms at sample " + Str(HostFifoW) + #LF$ : EndIf
  HostPumpAt = now
  n = SoundSamples - HostSndRead
  If n > #SOUND_RING
    HostSndOverruns + 1                  ; (the machine's thread: counted only, the event text is the sound thread's)
    HostSndRead = SoundSamples - #SOUND_RING
  EndIf
  While HostSndRead < SoundSamples
    HostSndFifo(HostFifoW & (#HOST_SND_FIFO - 1)) = SoundRing(HostSndRead & (#SOUND_RING - 1))
    HostSndRead + 1 : HostFifoW + 1
  Wend
  If HostSndThread = 0 : HostSndThread = CreateThread(@HostSoundThread(), 0) : EndIf
EndProcedure

Procedure HostSoundClose()
  Protected f.i
  If HostSndThread : HostSndQuit = 1 : WaitThread(HostSndThread, 1000) : HostSndThread = 0 : EndIf
  If HostSndOpen : waveOutReset_(HostSndDevice) : waveOutClose_(HostSndDevice) : HostSndOpen = 0 : EndIf
  If HostWavFile
    HostWavHeader(HostWavFile, HostWavBytes) : CloseFile(HostWavFile) : HostWavFile = 0
    f = CreateFile(#PB_Any, HostWav$ + ".txt")
    If f
      WriteString(f, "underruns " + Str(HostSndUnderruns) + " skips " + Str(HostSndSkips) + " ring overruns " + Str(HostSndOverruns) + " step at the end " + StrF(HostSndStep / 65536.0, 5) + #LF$ + HostSndEvents$ + "machine thread gaps:" + #LF$ + HostPumpGaps$)
      CloseFile(f)
    EndIf
  EndIf
EndProcedure
