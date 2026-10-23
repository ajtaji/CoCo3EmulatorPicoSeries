"""Print the KeyTable DataSection of src/keyboard.pmi: host byte (0-135) -> CoCo 3 matrix key.

Each entry is (row << 4) | column, plus $100 for SHIFT; $FFFF = no key. Rows and columns are those of
MAME's coco3.cpp keyboard (row = PIA0 PA bit, column = PIA0 PB bit).
"""
t = [0xFFFF] * 136
for c in range(ord('@'), ord('Z') + 1):
    n = c - 64
    t[c] = ((n >> 3) << 4) | (n & 7)
for c in range(ord('a'), ord('z') + 1):
    t[c] = t[c - 32]
for i, c in enumerate('01234567'):
    t[ord(c)] = 0x40 | i
t[ord('8')], t[ord('9')] = 0x50, 0x51
for c, v in zip(':;,-./', range(0x52, 0x58)):
    t[ord(c)] = v
for c, v in zip('!"#$%&\'', range(0x141, 0x148)):
    t[ord(c)] = v
for c, v in zip('()*+<=>?', range(0x150, 0x158)):
    t[ord(c)] = v
t[32] = 0x37                                   # SPACE
t[13] = t[10] = 0x60                           # ENTER
t[12] = 0x61                                   # CLEAR
t[27] = t[3] = 0x62                            # BREAK
t[8] = t[127] = 0x35                           # left arrow
t[9] = 0x36                                    # right arrow
t[0x80], t[0x81], t[0x82], t[0x83] = 0x33, 0x34, 0x35, 0x36   # up, down, left, right
t[0x84], t[0x85] = 0x65, 0x66                  # F1, F2
print('  KeyTable:')
for i in range(0, 136, 8):
    print('  Data.u ' + ', '.join('$%04X' % v for v in t[i:i + 8]))
