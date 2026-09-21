#!/bin/bash
# Guard for the native build: every Gson-serialized class of the Kura REST bundles must have a reflection entry.
# Usage: check-dto-metadata.sh <plugins dir> <reflect-config.json>... ; exits 1 and lists the classes without metadata.
set -u
PLUGINS=$1; shift
python3 - "$PLUGINS" "$@" <<'PY'
import sys, glob, zipfile, json, re, struct, os
plugins, configs = sys.argv[1], sys.argv[2:]
known = set()
for c in configs:
    for e in json.load(open(c)):
        if isinstance(e, dict) and 'name' in e:
            known.add(e['name'])
BUNDLES = re.compile(r'org\.eclipse\.kura\.(rest\.|request\.handler\.jaxrs|core\.identity|cloudconnection)')
PACKAGE = re.compile(r'\.(dto|request|response)$')
NAME = re.compile(r'(DTO|Dto|Request|Response)$')
ACC_INTERFACE, ACC_ABSTRACT = 0x0200, 0x0400

def access_flags(data):
    pos = 8; count = struct.unpack('>H', data[pos:pos + 2])[0]; pos += 2; i = 1
    while i < count:
        tag = data[pos]; pos += 1
        if tag in (7, 8, 16, 19, 20): pos += 2
        elif tag in (3, 4, 9, 10, 11, 12, 17, 18): pos += 4
        elif tag in (5, 6): pos += 8; i += 1
        elif tag == 15: pos += 3
        elif tag == 1: pos += 2 + struct.unpack('>H', data[pos:pos + 2])[0]
        else: raise ValueError(tag)
        i += 1
    return struct.unpack('>H', data[pos:pos + 2])[0]

missing = []
for j in sorted(glob.glob(os.path.join(plugins, '*', '*.jar'))):
    if not BUNDLES.search(os.path.basename(j)): continue
    with zipfile.ZipFile(j) as z:
        for n in z.namelist():
            if not n.endswith('.class') or n.endswith('package-info.class') or re.search(r'\$\d+\.class$', n): continue
            cls = n[:-6].replace('/', '.')
            pkg, simple = cls.rsplit('.', 1)
            if not (PACKAGE.search(pkg) or NAME.search(simple.split('$')[-1])): continue
            flags = access_flags(z.read(n))
            if flags & (ACC_INTERFACE | ACC_ABSTRACT): continue
            if cls not in known: missing.append(cls)
if missing:
    print(f"{len(missing)} serialized classes without reflection metadata:")
    for m in missing: print("  " + m)
    sys.exit(1)
print("all serialized REST classes have reflection metadata")
PY
