#!/bin/bash
# On the Pi: one native run of the JNI profile with the bundle dump, listing the fragment libraries mapped in the process; restores Kura afterwards.
set -u
B=/root/kura-bench; W=$B/graal-work-jni; mkdir -p $W/out
CRL=/opt/eclipse/kura/user/security/cacerts.ks.crl
D=/opt/eclipse/kura
NL="-Djava.library.path=$W/native-libs"
PROPS="-Dkura.os.version=debian -Dkura.arch=aarch64 -Dtarget.device=aarch64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
JVMF="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED"
trap 'pkill -x kura-native 2>/dev/null; pkill -x java 2>/dev/null; sleep 1; [ -f /root/kura-bench/cacerts.ks.crl.legacy ] && { cp -p /root/kura-bench/cacerts.ks.crl.legacy $CRL; rm -rf $CRL.d; }; chown -R kurad:kurad /opt/eclipse/kura; systemctl is-active kura >/dev/null || systemctl start kura; echo "### $(date -Is) kura $(systemctl is-active kura)"' EXIT
systemctl stop kura; sleep 3; pkill -x java 2>/dev/null; sleep 1
OFF=$(wc -l < /var/log/kura.log)
$W/out/kura-native -Xmx512m -Dkura.atomos.dump=true -Dkura.atomos.dumpAfter=45 -Datomos.lib.dir=$B/host_lib_jni $PROPS $NL > $B/pi-native-jni-verify.out 2>&1 &
P=$!; sleep 55
echo "=== loaded .so from fragments"; grep -oE "/[^ ]*(libdkcomm|libhidapi|libEurotechLinuxUdev|libnetty_transport|libudev)[^ ]*\.so[^ ]*" /proc/$P/maps | sort -u
echo "=== log"; tail -n +$OFF /var/log/kura.log | grep -iE "udev|Usb|hidapi|dkcomm|comm|serial|UnsatisfiedLink|NativeCode|Exception|ERROR" | grep -vE "Registering|Seeding|Merging|metatype|commit|snapshot|CommandExecutor|Communication" | cut -c25-220 | sort -u | head -40
echo "=== bundles"; sed -n '/=== after/,$p' $B/pi-native-jni-verify.out | grep -E "bundles by state|^(INSTALLED|RESOLVED|STARTING) " | cut -c1-160
kill -TERM $P; wait $P 2>/dev/null
