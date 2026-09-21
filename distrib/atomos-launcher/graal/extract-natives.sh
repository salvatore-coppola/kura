#!/bin/bash
# Inside the container: extract the shared libraries carried by the platform fragments into /work/native-libs.
set -u
OUT=/work/native-libs; rm -rf $OUT; mkdir -p $OUT
[ -e /usr/lib64/libudev.so.0 ] || ln -sf /usr/lib64/libudev.so.1 /usr/lib64/libudev.so.0 2>/dev/null
python3 - "$OUT" "$(uname -m)" <<'PY'
import sys, glob, zipfile, os, re
out, arch = sys.argv[1], sys.argv[2]
alt = arch.replace('x86_64', 'x86-64').replace('aarch64', 'aarch_64')
for j in sorted(glob.glob('/opt/eclipse/kura/plugins/*/*.jar')):
    with zipfile.ZipFile(j) as z:
        try: mf = z.read('META-INF/MANIFEST.MF').decode('utf-8', 'replace').replace('\r', '')
        except KeyError: continue
        if 'Bundle-NativeCode' not in mf: continue
        name = os.path.basename(j)
        if arch not in name and alt not in name: continue
        for n in z.namelist():
            if n.endswith('.so'):
                open(os.path.join(out, os.path.basename(n)), 'wb').write(z.read(n)); os.chmod(os.path.join(out, os.path.basename(n)), 0o755)
                print(f"{name} -> {os.path.basename(n)}")
PY
ls -la $OUT
