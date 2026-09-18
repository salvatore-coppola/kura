#!/bin/bash
# Host side: agent run, native build and REST smoke test of the REST profile on x86_64.
set -u
A=/home/scoppola/kura-develop/distrib/atomos-launcher; W=/home/scoppola/kura-native-bench/graal-work-rest
RUN="docker run --rm --privileged -e PROFILE=rest -v $A/target:/atomos:ro -v $A/graal:/graal:ro -v $W:/work kura-graal:21"
echo "### agent $(date -Is)"; rm -rf $W/cfg; $RUN bash /graal/agent-run.sh 100 2>&1 | grep -E "^REST|bundles by state|predefined-classes|reflect-config" | cut -c1-160; grep -oE '"nameInfo":"[^"]+"' $W/cfg/predefined-classes-config.json | head -12
echo "### build $(date -Is)"; $RUN bash /graal/build-native.sh -J-Xmx10g > $W/build.log 2>&1; grep -E "Finished generating|Error|Caused by|in total|Peak RSS" $W/build.log | head -4
echo "### rest test $(date -Is)"
$RUN bash -c '. /graal/common.sh; rm -rf /work/atomos_lib; mkdir -p /work/atomos_lib; for j in $(echo "$(build_cp)" | tr ":" " "); do case "$j" in /atomos/org.eclipse.kura.atomos.launcher*) continue;; /atomos/lib/*|*/org.eclipse.osgi-3.21.0.jar) ln -s "$j" "/work/atomos_lib/$(basename "$j")"; continue;; esac; lvl=$(basename "$(dirname "$j")"); ln -s "$j" "/work/atomos_lib/${lvl}__$(basename "$j")"; done; rm -f /var/log/kura.log
t0=$(awk "{print \$1}" /proc/uptime); /work/out/kura-native -Xmx512m -Datomos.lib.dir=/work $KURA_PROPS -Dkura.atomos.dump=true -Dkura.atomos.dumpAfter=40 > /work/native-run.out 2>&1 & P=$!
tj=; tr=; for i in $(seq 1 600); do c=$(curl -sk -m 1 -o /dev/null -w "%{http_code}" https://127.0.0.1:443/services/session/v1/currentIdentity); t=$(awk "{print \$1}" /proc/uptime); [ "$c" != 000 ] && [ -z "$tj" ] && tj=$(awk -v a=$t0 -v b=$t "BEGIN{printf \"%.2f\", b-a}"); [ "$c" = 401 ] && { tr=$(awk -v a=$t0 -v b=$t "BEGIN{printf \"%.2f\", b-a}"); break; }; kill -0 $P 2>/dev/null || break; sleep 0.1; done
echo "Jetty up: ${tj:-NA} s, REST 401: ${tr:-NA} s"; sleep 3
echo "login: $(curl -sk -m 5 -c /work/c.txt -X POST -H "Content-Type: application/json" -d "{\"username\":\"admin\",\"password\":\"admin\"}" -o /dev/null -w "%{http_code}" https://127.0.0.1:443/services/session/v1/login/password)"
curl -sk -m 5 -b /work/c.txt -o /work/x.json https://127.0.0.1:443/services/session/v1/xsrfToken; X=$(grep -oE "\"xsrfToken\":\"[^\"]+\"" /work/x.json | cut -d\" -f4)
for p in session/v1/currentIdentity inventory/v1/bundles system/v1/properties/kura identity/v1/identities deviceConfig/v2/configurableComponents/pids keystores/v2/keystores; do echo "GET $p: $(curl -sk -m 10 -b /work/c.txt -H "X-XSRF-Token: $X" -o /work/r.json -w "%{http_code}" https://127.0.0.1:443/services/$p) $(head -c 100 /work/r.json | tr -d "\n")"; done
sleep 40; echo "RSS kB: $(awk "/VmRSS/{print \$2}" /proc/$P/status)"; grep -E "bundles by state" /work/native-run.out | tail -1; grep -E "state=16" /work/native-run.out | head -3 | cut -c1-160; echo "-- errors: $(grep -cE "ERROR" /var/log/kura.log) log / $(grep -ciE "exception" /work/native-run.out) out"; grep -E "ERROR|Exception" /var/log/kura.log | grep -v ClockService | head -3 | cut -c25-200; kill -TERM $P; wait $P 2>/dev/null; echo "binary: $(stat -c %s /work/out/kura-native)"'
echo "### done $(date -Is)"
