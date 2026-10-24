# Scan a --wav recording of the desktop CoCo 3 (build/CoCo3.exe --wav f.wav --mute ...) for timing glitches
# in a square-wave tune: half periods more than 3 samples off their neighbours. Usage: py -3 tools/sound_scan.py f.wav
import sys, wave, struct, statistics
w = wave.open(sys.argv[1]); n = w.getnframes(); d = struct.unpack('<%dh' % n, w.readframes(n))
runs = []; start = 0
for i in range(1, n):
    if d[i] != d[i-1]:
        runs.append((start, i - start, d[start])); start = i
levels = set(r[2] for r in runs[5:])
big = []
for k in range(6, len(runs) - 6):
    nb = [runs[k+j][1] for j in (-6,-4,-2,2,4,6)]
    m = statistics.median(nb)
    if runs[k][1] < 400 and abs(runs[k][1] - m) > 3: big.append(runs[k])
print(sys.argv[1], 'seconds %.1f' % (n/48000), 'levels', sorted(levels), 'glitches >3 samples', len(big), 'per s %.2f' % (len(big)/(n/48000)))
