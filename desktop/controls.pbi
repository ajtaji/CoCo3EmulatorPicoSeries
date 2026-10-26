; The one table of the desktop window's controls: every PC key the window reads, what it is on the CoCo 3
; (a byte for keyboard.pmi's queue) or what the window does with it, and when it applies. The key handling
; (CoCo3.pb, HostKeyDown), the Controls tab and the README's Controls section (--controls-md) all read it,
; so none of them can disagree with the others.

#CTL_KEY = 0        ; a PC key typed to the CoCo: value is the byte (keyboard.pmi's bytes)
#CTL_MOD = 1        ; a PC modifier held with a letter or digit: value is the byte sent before the key
#CTL_ACTION = 2     ; the window's own key: value is an #ACT_
#CTL_NOTE = 3       ; shown only: what has no single PC key

#CTL_ALWAYS = 0
#CTL_WINDOWED = 1   ; only in the window
#CTL_FULL = 2       ; only in full screen

Enumeration
  #ACT_NONE
  #ACT_RUNPAUSE
  #ACT_STEP
  #ACT_FRAME
  #ACT_RESET
  #ACT_FULLSPEED
  #ACT_MUTE
  #ACT_FULLSCREEN
  #ACT_LEAVEFULL
EndEnumeration

Structure Control
  kind.i
  pcKey.i           ; the #PB_Shortcut_ the OpenGL gadget reports; for #CTL_MOD the Windows VK held; 0 for a note
  when.i
  value.i
  pc$
  coco$
EndStructure
Global NewList Controls.Control()

Procedure ControlAdd(kind.i, pcKey.i, when.i, value.i, pc$, coco$)
  AddElement(Controls())
  Controls()\kind = kind : Controls()\pcKey = pcKey : Controls()\when = when : Controls()\value = value
  Controls()\pc$ = pc$ : Controls()\coco$ = coco$
EndProcedure

; Esc is BREAK in the window; in full screen Esc leaves full screen, so BREAK is also on End (always).
Procedure ControlsInit()
  ControlAdd(#CTL_NOTE, 0, #CTL_ALWAYS, 0, "letters, digits, punctuation, Space", "the same CoCo key, with SHIFT where the character needs it")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Return, #CTL_ALWAYS, 13, "Enter", "ENTER")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Escape, #CTL_WINDOWED, 27, "Esc (in the window)", "BREAK")
  ControlAdd(#CTL_KEY, #PB_Shortcut_End, #CTL_ALWAYS, 27, "End", "BREAK")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Home, #CTL_ALWAYS, 12, "Home", "CLEAR")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Up, #CTL_ALWAYS, $80, "Up", "up arrow")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Down, #CTL_ALWAYS, $81, "Down", "down arrow")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Left, #CTL_ALWAYS, $82, "Left", "left arrow")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Back, #CTL_ALWAYS, 8, "Backspace", "left arrow")
  ControlAdd(#CTL_KEY, #PB_Shortcut_Right, #CTL_ALWAYS, $83, "Right", "right arrow")
  ControlAdd(#CTL_KEY, #PB_Shortcut_F1, #CTL_ALWAYS, $84, "F1", "F1")
  ControlAdd(#CTL_KEY, #PB_Shortcut_F2, #CTL_ALWAYS, $85, "F2", "F2")
  ControlAdd(#CTL_MOD, #VK_MENU, #CTL_ALWAYS, $86, "Alt + a letter or digit", "ALT + that key")
  ControlAdd(#CTL_MOD, #VK_CONTROL, #CTL_ALWAYS, $87, "Ctrl + a letter or digit", "CTRL + that key")
  ControlAdd(#CTL_NOTE, 0, #CTL_ALWAYS, 0, "(none)", "joysticks and gamepad: not on the desktop yet - both sticks centred, fire buttons up")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_F5, #CTL_ALWAYS, #ACT_RUNPAUSE, "F5", "window: run / pause")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_F10, #CTL_ALWAYS, #ACT_STEP, "F10", "window: one instruction (paused)")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_F7, #CTL_ALWAYS, #ACT_FRAME, "F7", "window: one frame (paused)")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_F3, #CTL_ALWAYS, #ACT_RESET, "F3", "window: reset")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_F8, #CTL_ALWAYS, #ACT_FULLSPEED, "F8", "window: full speed on / off")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_F9, #CTL_ALWAYS, #ACT_MUTE, "F9", "window: mute on / off")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_F11, #CTL_ALWAYS, #ACT_FULLSCREEN, "F11", "window: full screen on / off")
  ControlAdd(#CTL_ACTION, #PB_Shortcut_Escape, #CTL_FULL, #ACT_LEAVEFULL, "Esc (in full screen)", "window: leave full screen")
EndProcedure

; The entry for a key the gadget reported, in the window (full = 0) or in full screen; 0 for none.
Procedure.i ControlFind(pcKey.i, full.i)
  ForEach Controls()
    If Controls()\pcKey = pcKey And (Controls()\kind = #CTL_KEY Or Controls()\kind = #CTL_ACTION)
      If Controls()\when = #CTL_ALWAYS Or (Controls()\when = #CTL_WINDOWED And full = 0) Or (Controls()\when = #CTL_FULL And full)
        ProcedureReturn @Controls()
      EndIf
    EndIf
  Next
  ProcedureReturn 0
EndProcedure

; The README's Controls table, from the same list.
Procedure.s ControlsMarkdown()
  Protected t$ = "| PC | CoCo 3 / window |" + #LF$ + "|---|---|" + #LF$
  ForEach Controls()
    t$ + "| " + Controls()\pc$ + " | " + Controls()\coco$ + " |" + #LF$
  Next
  ProcedureReturn t$
EndProcedure
