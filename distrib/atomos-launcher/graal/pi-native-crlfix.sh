#!/bin/bash
# On the Pi: rebuild the native image (the installed keystore bundle is already the patched one) and measure host-side starts with the CRL cache present.
set -u
B=/root/kura-bench; W=$B/graal-work
RUN="docker run --rm --privileged -v /opt/eclipse/kura:/opt/eclipse/kura:ro -v $B/atomos:/atomos:ro -v $B/graal:/graal:ro -v $W:/work kura-graal:21"
echo "### $(date -Is) native-image build (crl fix)"; $RUN bash /graal/build-native.sh -J-Xmx5g > $W/build-crlfix.log 2>&1; grep -E "Finished generating|Error|Caused by" $W/build-crlfix.log | head -3
LIB=$B/host_lib/atomos_lib; EX=$(cat $B/graal/profile-min.exclude); rm -rf $B/host_lib; mkdir -p $LIB
for l in 1 1s 2 2s 3 3s 4 4s 5 5s 6 6s; do for j in /opt/eclipse/kura/plugins/$l/*.jar; do echo "$j" | grep -qE "$EX|osgi-resource-locator|web2" && continue; ln -s "$j" "$LIB/${l}__$(basename $j)"; done; done
for j in $B/atomos/patches/*/*.jar; do echo "$j" | grep -q osgi-resource-locator && continue; ln -s "$j" "$LIB/$(basename $(dirname $j))__$(basename $j)"; done
ln -s $B/atomos/patches/2s/osgi-resource-locator-1.0.3.jar $LIB/2s__osgi-resource-locator-1.0.3.jar; ln -s $B/atomos/lib/org.apache.felix.atomos-1.0.0.jar $LIB/; ln -s /opt/eclipse/kura/plugins/org.eclipse.osgi-3.21.0.jar $LIB/
D=/opt/eclipse/kura
PROPS="-Dkura.os.version=debian -Dkura.arch=aarch64 -Dtarget.device=aarch64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
echo "### $(date -Is) host runs"; systemctl stop kura; while pgrep -x java >/dev/null; do sleep 0.5; done
run() { sync; echo 3 > /proc/sys/vm/drop_caches; sleep 2; : > /var/log/kura.log
  t0=$(awk '{print $1}' /proc/uptime); $W/out/kura-native -Xmx256m -Datomos.lib.dir=$B/host_lib $PROPS > $B/host-native.out 2>&1 & P=$!
  for i in $(seq 1 600); do grep -q "has started!" /var/log/kura.log 2>/dev/null && break; kill -0 $P 2>/dev/null || break; sleep 0.1; done
  t=$(awk '{print $1}' /proc/uptime); tf=$(awk -v a=$t0 -v b=$t 'BEGIN{printf "%.2f", b-a}'); sleep 30
  echo "$1: first has started ${tf}s, RSS30 $(awk '/VmRSS/{print $2}' /proc/$P/status) kB, CPU $(awk -v tck=100 '{printf "%.1f", ($14+$15)/tck}' /proc/$P/stat) s, log lines $(wc -l < /var/log/kura.log), errors $(grep -c ERROR /var/log/kura.log), OOM $(grep -c OutOfMemory $B/host-native.out)"
  kill -TERM $P; wait $P 2>/dev/null; sleep 2; }
ls -la /opt/eclipse/kura/user/security/ | grep -i crl
run "native+crlfix, CRL cache present (1)"; run "native+crlfix, CRL cache present (2)"; run "native+crlfix, CRL cache present (3)"
chown -R kurad:kurad /opt/eclipse/kura; systemctl start kura; sleep 3; systemctl is-active kura
echo "### $(date -Is) pi native crlfix done"
