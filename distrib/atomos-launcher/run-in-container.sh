#!/bin/bash
# usage: run-in-container.sh <levels e.g. "1 1s"> [timeout_s] [extra java opts...]
LEVELS=${1:-"1 1s"}; T=${2:-45}; shift 2 2>/dev/null
PATCHES="$(cd "$(dirname "$0")" && pwd)/patches/out"
VOLS=(-v "$(cd "$(dirname "$0")" && pwd)/target:/atomos")
for j in "$PATCHES"/*/*.jar; do [ -f "$j" ] || continue; lvl=$(basename "$(dirname "$j")"); VOLS+=(-v "$j:/opt/eclipse/kura/plugins/$lvl/$(basename "$j"):ro"); done
docker run --rm --privileged "${VOLS[@]}" kura-bench:jvm env EXCLUDE="${EXCLUDE:-}" bash -c '
LEVELS="$1"; T=$2; shift 2
CP=/atomos/org.eclipse.kura.atomos.launcher-6.0.0-SNAPSHOT.jar:/atomos/lib/org.apache.felix.atomos-1.0.0.jar:/opt/eclipse/kura/plugins/org.eclipse.osgi-3.21.0.jar
for l in $LEVELS; do for j in /opt/eclipse/kura/plugins/$l/*.jar; do if [ -n "${EXCLUDE:-}" ] && echo "$j" | grep -qE "$EXCLUDE"; then echo "excluded: $(basename $j)"; continue; fi; CP=$CP:$j; done; done
D=/opt/eclipse/kura
timeout $T java --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED \
 -Dkura.os.version=debian -Dkura.arch=x86_64 -Dtarget.device=x86_64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true \
 -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties \
 -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true \
 -Dkura.atomos.dump=true "$@" -cp $CP org.eclipse.kura.atomos.KuraAtomosLauncher > /tmp/launcher.out 2>&1 &
sleep $((T-12))
echo "-- ports while running:"; ss -ltnp 2>/dev/null | grep -E ":(443|4443|5002)\b" | cut -c1-80
echo "-- REST probe: $(curl -sk -m 5 -o /dev/null -w "%{http_code}" https://127.0.0.1:443/services/session/v1/currentIdentity)"
echo "-- RSS kB: $(awk "/VmRSS/{print \$2}" /proc/$(pgrep -x java | head -1)/status 2>/dev/null)"
wait
head -400 /tmp/launcher.out
echo "-- kura.log errors/warns:"; grep -E "ERROR|WARN|Exception" /var/log/kura.log 2>/dev/null | cut -c25-260 | sort | uniq -c | sort -rn | head -40
echo "-- http/keystore/rest lines:"; grep -E "HttpService|Https|KeystoreService|Jersey|jakartars|Whiteboard|ServerConnector|Started|Failed|Cannot" /var/log/kura.log 2>/dev/null | grep -vE "Registering|Seeding|Merging|has started" | cut -c25-220 | head -25
cp /var/log/kura.log /atomos/kura-atomos.log 2>/dev/null; echo "-- kura.log tail:"; tail -3 /var/log/kura.log 2>/dev/null | cut -c1-150; echo "-- kura.log lines: $(wc -l < /var/log/kura.log 2>/dev/null)"
echo "-- ports:"; ss -ltn 2>/dev/null | grep -E ":(443|4443)" | wc -l' _ "$LEVELS" "$T" "$@"
