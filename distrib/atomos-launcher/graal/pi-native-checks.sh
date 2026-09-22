#!/bin/bash
# On the Pi: rebuild the JNI profile with the current metadata, then run the open checks in native and on the JVM (same profile):
# authenticated REST flow on installer-default identities, MQTT plain and TLS against a local Mosquitto, serial/HID diagnostics,
# USB hotplug events, RSS with a smaller heap. Device state (snapshots, security dir, Kura service) is restored on exit.
set -u
B=/root/kura-bench; W=$B/graal-work-jni; D=/opt/eclipse/kura; SNAP=$D/user/snapshots; SEC=$D/user/security
restore() {
  pkill -x kura-native 2>/dev/null; pkill -x java 2>/dev/null; sleep 1
  [ -d $B/snapshots.bak ] && { rm -rf $SNAP; mv $B/snapshots.bak $SNAP; }
  [ -d $B/security.bak ] && { rm -rf $SEC; mv $B/security.bak $SEC; }
  chown -R kurad:kurad $D; docker rm -f kura-mosq >/dev/null 2>&1
  systemctl is-active kura >/dev/null || systemctl start kura; echo "### $(date -Is) kura $(systemctl is-active kura)"
}
trap restore EXIT
mkdir -p $B/atomos/patches/4s && cp $B/keystore-crlfix2.jar $B/atomos/patches/4s/org.eclipse.kura.core.keystore-2.0.0-SNAPSHOT.jar
RUN="docker run --rm --privileged -e PROFILE=jni -v $D:$D:ro -v $B/atomos:/atomos:ro -v $B/graal:/graal:ro -v $W:/work kura-graal:21"
if [ -z "${SKIP_BUILD:-}" ]; then
  echo "### $(date -Is) natives"; OUT=$W/native-libs bash $B/graal/extract-natives.sh | tail -6
  echo "### $(date -Is) native-image build (jni)"; $RUN bash /graal/build-native.sh -J-Xmx5g > $W/build.log 2>&1; grep -E "Finished generating|Error|Caused by|in total|Peak RSS" $W/build.log | head -4; grep -q "Finished generating" $W/build.log || { echo "build failed, aborting"; exit 1; }
fi
EX=$(cat $B/graal/profile-jni.exclude); PATCHED=$(ls $B/atomos/patches/*/*.jar | xargs -n1 basename | tr '\n' '|' | sed 's/|$//')
LIB=$B/host_lib_jni/atomos_lib; rm -rf $B/host_lib_jni; mkdir -p $LIB; CP=$B/atomos/org.eclipse.kura.atomos.launcher-6.0.0-SNAPSHOT.jar:$B/atomos/lib/org.apache.felix.atomos-1.0.0.jar:$D/plugins/org.eclipse.osgi-3.21.0.jar
for l in 1 1s 2 2s 3 3s 4 4s 5 5s 6 6s; do for j in $D/plugins/$l/*.jar; do echo "$j" | grep -qE "$EX" && continue; echo "$(basename $j)" | grep -qxE "$PATCHED" && continue; ln -s "$j" "$LIB/${l}__$(basename $j)"; CP=$CP:$j; done; done
for j in $B/atomos/patches/*/*.jar; do ln -s "$j" "$LIB/$(basename $(dirname $j))__$(basename $j)"; CP=$CP:$j; done
ln -s $B/atomos/lib/org.apache.felix.atomos-1.0.0.jar $LIB/; ln -s $D/plugins/org.eclipse.osgi-3.21.0.jar $LIB/
NL="-Djava.library.path=$W/native-libs"
PROPS="-Dkura.os.version=debian -Dkura.arch=aarch64 -Dtarget.device=aarch64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
echo "### $(date -Is) host checks"; systemctl stop kura; while pgrep -x java >/dev/null; do sleep 0.5; done
cp -a $SNAP $B/snapshots.bak; cp -a $SEC $B/security.bak
bash $B/graal/broker-up.sh $B/broker host 192.168.1.19
reset_state() { find $SNAP -name 'snapshot_*.xml' ! -name snapshot_0.xml -delete; rm -rf $SEC; cp -a $B/security.bak $SEC; [ -d $B/default-security ] && cp $B/default-security/*.ks $SEC/ && rm -rf $SEC/cacerts.ks.crl $SEC/cacerts.ks.crl.d; chown -R kurad:kurad $SEC; }
COMM=/dev/ttyS0; for d in /dev/ttyUSB0 /dev/ttyACM0; do [ -e $d ] && COMM=$d; done
echo "usb devices: $(lsusb 2>/dev/null | grep -vi "root hub" | cut -d' ' -f6- | tr '\n' ';')"; echo "serial for diag: $COMM; hidraw: $(ls /dev/hidraw* 2>/dev/null | tr '\n' ' ')"
DIAG="-Dkura.atomos.diag.comm=$COMM -Dkura.atomos.diag.hid=true -Dkura.atomos.dump=true"
check() { # label settle cmd...
  local label=$1 settle=$2; shift 2; reset_state; : > /var/log/kura.log
  t0=$(awk '{print $1}' /proc/uptime); "$@" > $B/checks-$label.out 2>&1 & P=$!
  tr=; for k in $(seq 1 900); do c=$(curl -sk -m 1 -o /dev/null -w "%{http_code}" https://127.0.0.1:443/services/session/v1/currentIdentity); [ "$c" = 401 ] && { tr=$(awk -v a=$t0 -v b="$(awk '{print $1}' /proc/uptime)" 'BEGIN{printf "%.1f", b-a}'); break; }; kill -0 $P 2>/dev/null || break; sleep 0.2; done
  echo "== $label: REST 401 at ${tr:-NA} s"; sleep 3
  bash $B/graal/rest-session-test.sh | sed 's/^/   /'
  grep -E "comm diag|hid diag" $B/checks-$label.out | sed 's/^/   /'
  bash $B/graal/mqtt-test.sh mqtt://127.0.0.1:1883 | sed 's/^/   plain /'
  bash $B/graal/mqtt-test.sh mqtts://127.0.0.1:8883 $B/broker/certs/ca.crt | sed 's/^/   tls /'
  echo "   broker: $(docker logs kura-mosq 2>&1 | grep -E 'New client connected' | tail -2 | cut -c1-120 | tr '\n' '|')"
  echo "   usb/hotplug log: $(grep -iE 'udev|usb|hotplug|tty' /var/log/kura.log | grep -viE 'Registering|Seeding|Merging|metatype|commit|Bundle-|configur' | tail -4 | cut -c25-160 | tr '\n' '|')"
  while awk -v a=$t0 -v b="$(awk '{print $1}' /proc/uptime)" -v s=$settle 'BEGIN{exit !(b-a<s)}'; do sleep 2; done
  echo "   RSS@${settle}s $(( $(awk '/VmRSS/{print $2}' /proc/$P/status)/1024 )) MB, CPU $(awk '{printf "%.1f", ($14+$15)/100}' /proc/$P/stat) s, threads $(awk '/Threads/{print $2}' /proc/$P/status), log errors $(grep -c ' ERROR ' /var/log/kura.log)"
  grep ' ERROR ' /var/log/kura.log | grep -v ClockService | cut -c25-200 | head -3 | sed 's/^/   ERR /'
  grep -E "bundles by state" $B/checks-$label.out | tail -1 | sed 's/^/   /'
  kill -TERM $P; wait $P 2>/dev/null; sleep 2; pkill -x java 2>/dev/null; pkill -x kura-native 2>/dev/null; sleep 1
}
JVMF="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED"
check jvm 120 java $JVMF -XX:TieredStopAtLevel=1 -XX:+UseSerialGC -Xms64m -Xmx1024m $PROPS $NL $DIAG -cp "$CP" org.eclipse.kura.atomos.KuraAtomosLauncher
check native512 120 $W/out/kura-native -Xmx512m -Datomos.lib.dir=$B/host_lib_jni $PROPS $NL $DIAG
check native256 180 $W/out/kura-native -Xmx256m -Datomos.lib.dir=$B/host_lib_jni $PROPS $NL $DIAG
echo "### $(date -Is) pi checks done"
