"""Type on the CoCo 3 from this PC's keyboard (Windows console), and see what the board says.

    py -3 tools/console.py --port COM7

Keys go to the CoCo keyboard as they are typed. ENTER, BACKSPACE (the CoCo's left arrow), the four
arrows, ESC (BREAK), HOME (CLEAR), F1 and F2 are mapped; Alt+key and Ctrl+key are not (the CoCo's
ALT and CTRL are sent with F3 / F4 followed by the key). Ctrl+] then a letter is a firmware monitor
command: s status, t the text on the screen, f full speed on/off, v periodic status on/off, r reset.
Ctrl+Q quits. Pasted text is sent whole; the firmware types it at the CoCo's pace (about 12 keys a second).
"""
import argparse
import msvcrt
import sys
import threading
import time

import serial

EXTENDED = {72: 0x80, 80: 0x81, 75: 0x82, 77: 0x83, 59: 0x84, 60: 0x85, 61: 0x86, 62: 0x87, 71: 12}

p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
p.add_argument('--port', required=True)
p.add_argument('--quiet', action='store_true', help='hide the periodic COCO status lines')
a = p.parse_args()
port = serial.Serial(a.port, 115200, timeout=0.05)
stop = False


def reader():
    buf = b''
    while not stop:
        try:
            data = port.read(4096)
        except serial.SerialException:
            print('\n[console] the port went away', flush=True)
            return
        if not data:
            continue
        buf += data
        while b'\n' in buf:
            line, buf = buf.split(b'\n', 1)
            s = line.decode('latin-1').rstrip('\r')
            if a.quiet and s.startswith('COCO frames='):
                continue
            print(s, flush=True)


threading.Thread(target=reader, daemon=True).start()
print('[console] typing goes to the CoCo 3. Ctrl+Q quits, Ctrl+] then a letter is a monitor command.', flush=True)
while True:
    ch = msvcrt.getwch()
    if ch == '\x11':
        break
    if ch in ('\x00', '\xe0'):
        code = ord(msvcrt.getwch())
        if code in EXTENDED:
            port.write(bytes([EXTENDED[code]]))
        continue
    if ch == '\x1d':
        port.write(b'\x1d' + msvcrt.getwch()[:1].encode('latin-1', 'replace'))
        continue
    if ch == '\x08':
        port.write(b'\x08')
        continue
    o = ord(ch)
    if o < 256:
        port.write(bytes([o]))
stop = True
time.sleep(0.1)
port.close()
