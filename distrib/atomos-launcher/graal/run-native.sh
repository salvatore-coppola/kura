#!/bin/bash
# Inside kura-graal: start the native image, probe readiness and report states. usage: run-native.sh [seconds] [extra runtime options]
set -u
. /graal/common.sh
T=${1:-60}; shift 2>/dev/null
rm -f /var/log/kura.log; mkdir -p /work/out
t0=$(awk '{print $1}' /proc/uptime)
/work/out/kura-native $KURA_PROPS -Dkura.atomos.dump=true -Dkura.atomos.diag=true -Dkura.atomos.dumpAfter=$((T-15)) "$@" > /work/native-run.out 2>&1 &
P=$!
for i in $(seq 1 $((T*5))); do grep -q "has started!" /var/log/kura.log 2>/dev/null && { t=$(awk '{print $1}' /proc/uptime); echo "first 'has started' after $(awk -v a=$t0 -v b=$t 'BEGIN{printf "%.2f", b-a}') s"; break; }; kill -0 $P 2>/dev/null || { echo "process exited early"; break; }; sleep 0.2; done
sleep 5; echo "-- RSS kB: $(awk '/VmRSS/{print $2}' /proc/$P/status 2>/dev/null)"
while kill -0 $P 2>/dev/null && awk -v a="$t0" -v b="$(awk '{print $1}' /proc/uptime)" -v t=$T 'BEGIN{exit !(b-a<t)}'; do sleep 1; done
echo "-- RSS kB at ${T}s: $(awk '/VmRSS/{print $2}' /proc/$P/status 2>/dev/null)"
echo "-- states:"; grep -E "framework started|bundles by state" /work/native-run.out | tail -2
echo "-- not active / failures:"; grep -E "^(INSTALLED|RESOLVED|STARTING) |state=16|Exception|Error" /work/native-run.out | grep -vE " (java|jdk)\.|^RESOLVED" | head -20 | cut -c1-200
echo "-- kura.log lines: $(wc -l < /var/log/kura.log 2>/dev/null)"; grep -E "has started|ERROR|Exception" /var/log/kura.log 2>/dev/null | tail -6 | cut -c25-180
kill -TERM $P 2>/dev/null; wait $P 2>/dev/null; echo "-- exit: $?"; cp /var/log/kura.log /work/native-kura.log 2>/dev/null; ls -la /work/out/kura-native | awk '{print "binary bytes:", $5}'
