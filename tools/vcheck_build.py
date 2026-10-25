# Make the RP2350 check build that runs both renderers on every kernel call and counts differences
# (tests/vcheck.txt reads the counts): build/vcheck/CoCo3, with the 6809 core beside it.
#   py -3 tools/vcheck_build.py [--core-commit 61d7444]      then build build/vcheck/CoCo3/rp2350/<wrapper>
# The core is taken from ../6809EmulatorPicoSeries at the commit given (default: its HEAD), never from its
# working tree, which another worker may be changing.
import argparse, pathlib, re, shutil, subprocess
root = pathlib.Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser(); ap.add_argument('--core-commit', default='HEAD'); a = ap.parse_args()
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
rename(src / 'video_t2.pmi', 'T2')
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
body = out / 'CoCo3' / 'rp2350' / 'coco3_body.pico2'; t = body.read_text(encoding='utf-8')
t, n = re.subn(r'(XIncludeFile "\.\./src/video_t2\.pmi"[^\n]*\n)', r'\1XIncludeFile "../src/video_portable.pmi"\nXIncludeFile "../src/video_check.pmi"\n', t)
assert n == 1
body.write_text(t, encoding='utf-8')
print('check build tree:', out / 'CoCo3', '(core', a.core_commit + ')')
