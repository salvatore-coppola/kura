#!/bin/bash
# On the Pi: build the JNI profile native image (USB/HID/serial fragments), then compare JVM vs native on the host (Kura service stopped meanwhile).
set -u
B=/root/kura-bench; W=$B/graal-work-jni; mkdir -p $W/out
CRL=/opt/eclipse/kura/user/security/cacerts.ks.crl
trap 'pkill -x kura-native 2>/dev/null; pkill -x java 2>/dev/null; sleep 1; [ -f /root/kura-bench/cacerts.ks.crl.legacy ] && { cp -p /root/kura-bench/cacerts.ks.crl.legacy $CRL; rm -rf $CRL.d; }; chown -R kurad:kurad /opt/eclipse/kura; systemctl is-active kura >/dev/null || systemctl start kura; echo "### $(date -Is) kura $(systemctl is-active kura)"' EXIT
mkdir -p $B/atomos/patches/4s && cp /root/kura-bench/keystore-crlfix2.jar $B/atomos/patches/4s/org.eclipse.kura.core.keystore-2.0.0-SNAPSHOT.jar
RUN="docker run --rm --privileged -e PROFILE=jni -v /opt/eclipse/kura:/opt/eclipse/kura:ro -v $B/atomos:/atomos:ro -v $B/graal:/graal:ro -v $W:/work kura-graal:21"
echo "### $(date -Is) natives"; OUT=$W/native-libs bash $B/graal/extract-natives.sh | tail -6
echo "### $(date -Is) native-image build (jni)"; $RUN bash /graal/build-native.sh -J-Xmx5g > $W/build.log 2>&1; grep -E "Finished generating|Error|Caused by|in total|Peak RSS" $W/build.log | head -4; grep -q "Finished generating" $W/build.log || { echo "build failed, aborting"; exit 1; }
EX=$(cat $B/graal/profile-jni.exclude); PATCHED=$(ls $B/atomos/patches/*/*.jar | xargs -n1 basename | tr '\n' '|' | sed 's/|$//')
LIB=$B/host_lib_jni/atomos_lib; rm -rf $B/host_lib_jni; mkdir -p $LIB; CP=$B/atomos/org.eclipse.kura.atomos.launcher-6.0.0-SNAPSHOT.jar:$B/atomos/lib/org.apache.felix.atomos-1.0.0.jar:/opt/eclipse/kura/plugins/org.eclipse.osgi-3.21.0.jar
for l in 1 1s 2 2s 3 3s 4 4s 5 5s 6 6s; do for j in /opt/eclipse/kura/plugins/$l/*.jar; do echo "$j" | grep -qE "$EX" && continue; echo "$(basename $j)" | grep -qxE "$PATCHED" && continue; ln -s "$j" "$LIB/${l}__$(basename $j)"; CP=$CP:$j; done; done
for j in $B/atomos/patches/*/*.jar; do ln -s "$j" "$LIB/$(basename $(dirname $j))__$(basename $j)"; CP=$CP:$j; done
ln -s $B/atomos/lib/org.apache.felix.atomos-1.0.0.jar $LIB/; ln -s /opt/eclipse/kura/plugins/org.eclipse.osgi-3.21.0.jar $LIB/; echo "lib jars: $(ls $LIB | wc -l)"
D=/opt/eclipse/kura
NL="-Djava.library.path=$W/native-libs"
PROPS="-Dkura.os.version=debian -Dkura.arch=aarch64 -Dtarget.device=aarch64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
echo "### $(date -Is) host runs"; systemctl stop kura; while pgrep -x java >/dev/null; do sleep 0.5; done
cp -p /opt/eclipse/kura/user/snapshots/snapshot_0.xml /tmp/snap0.bak 2>/dev/null; ls /opt/eclipse/kura/user/snapshots > /tmp/snaps.before
measure() { # label cmd...
  local label=$1; shift; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 2; : > /var/log/kura.log
  t0=$(awk '{print $1}' /proc/uptime); "$@" > $B/host-rest.out 2>&1 & P=$!
  tj=; tr=; for k in $(seq 1 900); do c=$(curl -sk -m 1 -o /dev/null -w "%{http_code}" https://127.0.0.1:443/services/session/v1/currentIdentity); t=$(awk '{print $1}' /proc/uptime); [ "$c" != 000 ] && [ -z "$tj" ] && tj=$(awk -v a=$t0 -v b=$t 'BEGIN{printf "%.1f", b-a}'); [ "$c" = 401 ] && { tr=$(awk -v a=$t0 -v b=$t 'BEGIN{printf "%.1f", b-a}'); break; }; kill -0 $P 2>/dev/null || break; sleep 0.2; done
  sleep 5; local rss1=$(awk '/VmRSS/{print $2}' /proc/$P/status); [ "$label" = "${label#*bench}" ] && { grep -iE "udev|UsbService|UnsatisfiedLink|Comm|hidapi" /var/log/kura.log | grep -vE "Registering|Seeding|Merging|metatype|commit" | head -5 | cut -c25-180 | sed 's/^/    /'; }
  while awk -v a=$t0 -v b="$(awk '{print $1}' /proc/uptime)" 'BEGIN{exit !(b-a<90)}'; do sleep 1; done
  echo "$label: Jetty ${tj:-NA}s, REST401 ${tr:-NA}s, RSS@ready $((rss1/1024)) MB, RSS@90s $(( $(awk '/VmRSS/{print $2}' /proc/$P/status)/1024 )) MB, CPU $(awk -v tck=100 '{printf "%.1f", ($14+$15)/tck}' /proc/$P/stat) s, threads $(awk '/Threads/{print $2}' /proc/$P/status), errors $(grep -c ' ERROR ' /var/log/kura.log)"
  kill -TERM $P; wait $P 2>/dev/null; sleep 2; pkill -x java 2>/dev/null; pkill -x kura-native 2>/dev/null; sleep 1
}
JVMF="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED"
measure "jvm-jni (C1, Xmx1024)" java $JVMF -XX:TieredStopAtLevel=1 -XX:+UseSerialGC -Xms64m -Xmx1024m $PROPS $NL -cp "$CP" org.eclipse.kura.atomos.KuraAtomosLauncher
measure "native-jni (Xmx512)" $W/out/kura-native -Xmx512m -Datomos.lib.dir=$B/host_lib_jni $PROPS $NL
for n in 2 3; do measure "jvm-jni bench $n" java $JVMF -XX:TieredStopAtLevel=1 -XX:+UseSerialGC -Xms64m -Xmx1024m $PROPS $NL -cp "$CP" org.eclipse.kura.atomos.KuraAtomosLauncher; measure "native-jni bench $n" $W/out/kura-native -Xmx512m -Datomos.lib.dir=$B/host_lib_jni $PROPS $NL; done
echo "### $(date -Is) restore"; chown -R kurad:kurad /opt/eclipse/kura; systemctl start kura; sleep 3; systemctl is-active kura
echo "### $(date -Is) pi native jni done"
