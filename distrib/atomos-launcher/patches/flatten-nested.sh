#!/bin/bash
# Repackages bundles that carry nested jars on their Bundle-ClassPath into flat jars (single-classloader runtimes such as
# Atomos and native-image only see the outer jar). usage: flatten-nested.sh <plugins dir> <out dir> <bundle basename prefix>...
set -e
PLUGINS=$1; mkdir -p "$2"; OUT=$(cd "$2" && pwd); shift 2
for prefix in "$@"; do
  for j in $PLUGINS/*/$prefix*.jar; do
    [ -f "$j" ] || continue
    level=$(basename "$(dirname "$j")"); name=$(basename "$j"); work=$(mktemp -d)
    bcp=$(unzip -p "$j" META-INF/MANIFEST.MF | tr -d '\r' | awk '/^Bundle-ClassPath:/{f=1; sub(/^Bundle-ClassPath: */,""); printf "%s", $0; next} f&&/^ /{sub(/^ /,""); printf "%s", $0; next} f{exit}')
    [ -n "$bcp" ] && [ "$bcp" != "." ] || { rm -rf "$work"; continue; }
    unzip -q "$j" -d "$work/outer"
    for entry in $(echo "$bcp" | tr ',' ' '); do
      [ "$entry" = "." ] && continue
      [ -f "$work/outer/$entry" ] || { echo "  $name: nested $entry missing"; continue; }
      mkdir -p "$work/nested"; unzip -q -o "$work/outer/$entry" -d "$work/nested" -x 'META-INF/MANIFEST.MF' 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' 'module-info.class' 'META-INF/versions/*'
      rm -f "$work/outer/$entry"
    done
    cp -rn "$work/nested/." "$work/outer/" 2>/dev/null || true
    python3 - "$work/outer/META-INF/MANIFEST.MF" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, 'rb').read().decode('utf-8').replace('\r\n', '\n')
s = re.sub(r'^Bundle-ClassPath:.*(?:\n .*)*', 'Bundle-ClassPath: .', s, flags=re.M)
open(p, 'w').write(s)
PY
    mkdir -p "$OUT/$level"; rm -f "$OUT/$level/$name"
    mv "$work/outer/META-INF/MANIFEST.MF" "$work/manifest.mf"
    jar cfm "$OUT/$level/$name" "$work/manifest.mf" -C "$work/outer" .
    echo "  flattened $level/$name: $bcp"
    rm -rf "$work"
  done
done
