#!/bin/bash
# On the Pi: run the debug native binary with the serial diagnostic, dump Java thread stacks with SIGQUIT, restore Kura on exit.
set -u
B=/root/kura-bench; W=$B/graal-work-jni; D=/opt/eclipse/kura
trap 'pkill -x kura-native 2>/dev/null; sleep 1; chown -R kurad:kurad $D; systemctl is-active kura >/dev/null || systemctl start kura; echo "### kura $(systemctl is-active kura)"' EXIT
systemctl stop kura; while pgrep -x java >/dev/null; do sleep 0.5; done
PROPS="-Dkura.os.version=debian -Dkura.arch=aarch64 -Dtarget.device=aarch64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
$W/out/kura-native -Xmx512m -Datomos.lib.dir=$B/host_lib_jni $PROPS -Djava.library.path=$W/native-libs -Dkura.atomos.diag.comm=${1:-/dev/ttyS0} -Dkura.atomos.diag.hid=true -Dkura.atomos.dump=true > $B/comm-probe.out 2>&1 & P=$!
sleep 30
echo "== stdout so far"; grep -E "diag|framework started" $B/comm-probe.out | cut -c1-200
echo "== CPU $(awk '{printf "%.1f", ($14+$15)/100}' /proc/$P/stat) s after 30 s"
kill -QUIT $P; sleep 5
echo "== main thread Java stack:"; awk '/^"main"/{f=1} f&&/^$/{exit} f' $B/comm-probe.out | head -45 | cut -c1-180
echo "== threads mentioning soda/comm/Serial:"; grep -nE "soda|Serial|dkcomm" $B/comm-probe.out | grep -v "comm diag" | head -12 | cut -c1-180
echo "== thread names:"; grep -E '^"' $B/comm-probe.out | sed 's/" .*/"/' | sort | uniq -c | sort -rn | head -12
kill -TERM $P; wait $P 2>/dev/null; echo "== after exit:"; grep -E "diag|framework started" $B/comm-probe.out | cut -c1-200
