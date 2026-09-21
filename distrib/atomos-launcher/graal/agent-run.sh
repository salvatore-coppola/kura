#!/bin/bash
# Inside kura-graal: run the minimal profile on the GraalVM JVM with the native-image tracing agent, then stop gracefully.
set -u
. /graal/common.sh
CP=$(build_cp); T=${1:-90}
mkdir -p /work/cfg; rm -f /var/log/kura.log
java -agentlib:native-image-agent=config-output-dir=/work/cfg,experimental-class-define-support --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED \
  $KURA_PROPS -Dkura.atomos.dump=true -Dkura.atomos.diag=true -Dkura.atomos.dumpAfter=$((T-20)) -cp "$CP" org.eclipse.kura.atomos.KuraAtomosLauncher > /work/agent-run.out 2>&1 &
P=$!; sleep $((T/2))
if [ "$PROFILE" = rest ]; then
  for i in $(seq 1 60); do curl -sk -m 2 -o /dev/null https://127.0.0.1:443/services/session/v1/currentIdentity && break; sleep 1; done
  bash /graal/rest-session-test.sh
fi
sleep $((T/2))
echo "-- states:"; grep -E "bundles by state" /work/agent-run.out | tail -1; grep -E "state=16|^INSTALLED" /work/agent-run.out | grep -vE " (java|jdk)\." | head -5
echo "-- kura.log lines: $(wc -l < /var/log/kura.log 2>/dev/null)"; grep -E "has started|ERROR" /var/log/kura.log | tail -4 | cut -c25-160
kill -TERM $P; wait $P 2>/dev/null; echo "-- exit: $?"
ls -la /work/cfg; for f in /work/cfg/*.json; do echo "$(basename $f): $(grep -c '"name"' $f) names"; done
cp /var/log/kura.log /work/agent-kura.log 2>/dev/null
