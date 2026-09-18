#!/bin/bash
# Inside kura-graal: A/B of the minimal profile, JVM (GraalVM JDK 21 in JVM mode) vs native image. usage: bench.sh <runs> <settle_s>
set -u
. /graal/common.sh
RUNS=${1:-3}; SETTLE=${2:-60}; OUT=/work/bench-min.csv
CP=$(build_cp)
[ -f $OUT ] || echo "label,run,t_first_started,t_quiet,rss60_kb,cpu60_s,threads" > $OUT
now() { awk '{print $1}' /proc/uptime; }
el() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", b-a}'; }
measure() { # label, command...
  local label=$1; shift
  for r in $(seq 1 $RUNS); do
    rm -f /var/log/kura.log; sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; sleep 2
    t0=$(now); "$@" > /work/bench-run.out 2>&1 & P=$!
    tf=; tq=; last=0; lastchg=$t0
    while :; do t=$(now); n=$(wc -l < /var/log/kura.log 2>/dev/null || echo 0)
      [ -z "$tf" ] && grep -q "has started!" /var/log/kura.log 2>/dev/null && tf=$(el $t0 $t)
      if [ "$n" != "$last" ]; then last=$n; lastchg=$t; fi
      if [ -n "$tf" ] && awk -v a=$lastchg -v b=$t 'BEGIN{exit !(b-a>5)}'; then tq=$(el $t0 $lastchg); break; fi
      awk -v a=$t0 -v b=$t 'BEGIN{exit !(b-a>120)}' && { tq=NA; break; }; sleep 0.2; done
    while awk -v a=$t0 -v b=$(now) -v s=$SETTLE 'BEGIN{exit !(b-a<s)}'; do sleep 1; done
    pid=$(pgrep -x java | head -1); [ -z "$pid" ] && pid=$(pgrep -x kura-native | head -1)
    rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status); thr=$(awk '/Threads/{print $2}' /proc/$pid/status); cpu=$(awk -v tck=100 '{printf "%.1f", ($14+$15)/tck}' /proc/$pid/stat)
    echo "$label,$r,${tf:-NA},${tq:-NA},$rss,$cpu,$thr" | tee -a $OUT
    kill -TERM $P; wait $P 2>/dev/null; sleep 2; pkill -x java; pkill -x kura-native; sleep 1
  done
}
JVMFLAGS="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED"
measure jvm-min-default java $JVMFLAGS $KURA_PROPS -cp "$CP" org.eclipse.kura.atomos.KuraAtomosLauncher
measure jvm-min-combomem java $JVMFLAGS -XX:TieredStopAtLevel=1 -XX:+UseSerialGC -Xms64m -Xmx1024m $KURA_PROPS -cp "$CP" org.eclipse.kura.atomos.KuraAtomosLauncher
measure native-min /work/out/kura-native -Datomos.lib.dir=/work $KURA_PROPS
measure native-min-xmx256 /work/out/kura-native -Xmx256m -Datomos.lib.dir=/work $KURA_PROPS
echo "bench done"
