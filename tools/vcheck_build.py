# Make the check build that runs the assembly kernels and the PureMetal ones on every call and counts
# differences (tests/vcheck.txt reads the counts): build/vcheck/CoCo3, with the 6809 core beside it.
#   py -3 tools/vcheck_build.py [--target rp2350|rp2040] [--core-commit 25cde43]
#   then build build/vcheck/CoCo3/rp2350/<wrapper> (video_t2.pmi) or rp2040/<wrapper> (video_t1.pmi)
# The core is taken from ../6809EmulatorPicoSeries at the commit given (default: its HEAD), never from its
# working tree, which may hold uncommitted changes.
import argparse, pathlib, re, shutil, subprocess
root = pathlib.Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser()
ap.add_argument('--core-commit', default='HEAD')
ap.add_argument('--target', choices=('rp2350', 'rp2040'), default='rp2350')
a = ap.parse_args()
fast = 'video_t2.pmi' if a.target == 'rp2350' else 'video_t1.pmi'
out = root / 'build' / 'vcheck'
shutil.rmtree(out, ignore_errors=True)
for d in ('src', 'rp2350', 'rp2040'):
    shutil.copytree(root / d, out / 'CoCo3' / d)
core = root.parent / '6809EmulatorPicoSeries'
(out / '6809EmulatorPicoSeries' / 'src').mkdir(parents=True)
for f in ('cpu6809.pico', 'cpu6809.pico2'):
    text = subprocess.run(['git', '-C', str(core), 'show', a.core_commit + ':src/' + f], check=True, capture_output=True).stdout
    (out / '6809EmulatorPicoSeries' / 'src' / f).write_bytes(text)
src = out / 'CoCo3' / 'src'
def rename(path, prefix):
    t = path.read_text(encoding='utf-8')
    for old, new in (('ProcedureRAM.l VideoScaleOut()', 'ProcedureRAM.l %sScaleOut()'), ('ProcedureRAM VideoBits()', 'ProcedureRAM %sBits()'),
                     ('ProcedureRAM VideoGraphicsRun()', 'ProcedureRAM %sGraphicsRun()'), ('ProcedureRAM VideoFill(index.i)', 'ProcedureRAM %sFill(index.i)'),
                     ('ProcedureRAM VideoCrc()', 'ProcedureRAM %sCrc()')):
        assert t.count(old) == 1, (path, old)
        t = t.replace(old, new % prefix)
    path.write_text(t, encoding='utf-8')
rename(src / fast, 'Fast')
rename(src / 'video_portable.pmi', 'Port')
shutil.copy(root / 'tests' / 'video_check.pmi', src / 'video_check.pmi')
mon = src / 'monitor.pmi'; t = mon.read_text(encoding='utf-8')
old = '  Say(" late=") : Num(CocoLate)\n'
assert t.count(old) == 1
t = t.replace(old, old + '  Say(" vcheck scale=") : Num(VcCalls(0)) : Say("/") : Num(VcBad(0)) : Say(" bits=") : Num(VcCalls(1)) : Say("/") : Num(VcBad(1))\n'
              '  Say(" graphics=") : Num(VcCalls(2)) : Say("/") : Num(VcBad(2)) : Say(" fill=") : Num(VcCalls(3)) : Say("/") : Num(VcBad(3))\n'
              '  Say(" crc=") : Num(VcCalls(4)) : Say("/") : Num(VcBad(4))\n'
              '  Say(" vcheck_bad=") : Num(VcBad(0) + VcBad(1) + VcBad(2) + VcBad(3) + VcBad(4))\n')
mon.write_text(t, encoding='utf-8')
body = out / 'CoCo3' / a.target / ('coco3_body.pico2' if a.target == 'rp2350' else 'coco3_body.pico')
t = body.read_text(encoding='utf-8')
include = 'XIncludeFile "../src/' + fast + '"'
t, n = re.subn('(' + re.escape(include) + r'[^\n]*\n)', lambda m: m.group(1) + 'XIncludeFile "../src/video_portable.pmi"\nXIncludeFile "../src/video_check.pmi"\n', t)
assert n == 1, include
body.write_text(t, encoding='utf-8')
print('check build tree:', out / 'CoCo3', '(' + a.target + ', ' + fast + ', core', a.core_commit + ')')
