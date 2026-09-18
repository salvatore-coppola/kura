#!/bin/bash
# Host side: rebuild the x86 native image with a patched keystore bundle and measure the CRL-cache effect on startup.
set -u
A=/home/scoppola/kura-develop/distrib/atomos-launcher
J=/home/scoppola/kura-develop/kura/org.eclipse.kura.core.keystore/target/org.eclipse.kura.core.keystore-2.0.0-SNAPSHOT.jar
W=/home/scoppola/kura-native-bench/graal-work-crl
RUN="docker run --rm --privileged -v $J:/opt/eclipse/kura/plugins/4s/org.eclipse.kura.core.keystore-2.0.0-SNAPSHOT.jar:ro -v $A/target:/atomos:ro -v $A/graal:/graal:ro -v $W:/work kura-graal:21"
echo "### build $(date -Is)"; $RUN bash /graal/build-native.sh -J-Xmx10g > $W/build.log 2>&1; grep -E "Finished generating|Error|Caused by" $W/build.log | head -3
echo "### crl effect $(date -Is)"
$RUN bash -c '. /graal/common.sh; bash /graal/run-native.sh 20 >/dev/null 2>&1
run() { rm -f /var/log/kura.log; t0=$(awk "{print \$1}" /proc/uptime); /work/out/kura-native -Xmx256m -Datomos.lib.dir=/work $KURA_PROPS > /work/t.out 2>&1 & P=$!
  for i in $(seq 1 600); do grep -q "has started!" /var/log/kura.log 2>/dev/null && break; sleep 0.1; done; t=$(awk "{print \$1}" /proc/uptime); sleep $1
  echo "$2: first has started after $(awk -v a=$t0 -v b=$t "BEGIN{printf \"%.2f\", b-a}") s, RSS after $1 s: $(awk "/VmRSS/{print \$2}" /proc/$P/status) kB, errors: $(grep -c ERROR /var/log/kura.log), stored: $(grep -c "storing CRLs...done" /var/log/kura.log)"; kill -TERM $P; wait $P 2>/dev/null; sleep 2; }
run 75 "no CRL cache"; ls -la /opt/eclipse/kura/user/security/ | grep -i crl; ls /opt/eclipse/kura/user/security/cacerts.ks.crl.d 2>/dev/null
run 30 "with CRL cache (file-based)"; run 30 "with CRL cache (file-based) 2"'
echo "### done $(date -Is)"
