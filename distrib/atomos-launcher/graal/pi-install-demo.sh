#!/bin/bash
# On the Pi: install the native Kura next to the classic one (/opt/eclipse/kura-native + kura-native.service), put the CRL fix
# in the classic Kura too (shared cache format), then exercise the switch classic -> native -> classic.
set -eu
B=/root/kura-bench; N=/opt/eclipse/kura-native; K=/opt/eclipse/kura
echo "### install"
mkdir -p $N/bin $N/atomos_lib $N/lib
cp $B/graal-work-jni/out/* $N/bin/
rm -f $N/atomos_lib/*; for l in $B/host_lib_jni/atomos_lib/*; do cp -L "$l" $N/atomos_lib/; done
cp $B/graal-work-jni/native-libs/*.so $N/lib/
chown -R kurad:kurad $N; chmod 755 $N/bin/kura-native
echo "binary $(stat -c %s $N/bin/kura-native) bytes, jars $(ls $N/atomos_lib | wc -l), libs $(ls $N/lib | wc -l), total $(du -sm $N | cut -f1) MB"
J=$(ls $K/plugins/4s/org.eclipse.kura.core.keystore-*.jar); [ -f $J.orig ] || cp -p $J $J.orig
cp $B/keystore-crlfix2.jar $J; chown kurad:kurad $J; echo "classic keystore bundle: $(md5sum $J | cut -c1-8) (orig $(md5sum $J.orig | cut -c1-8))"
cp -p $K/user/security/cacerts.ks.crl $B/cacerts.ks.crl.legacy-$(date +%Y%m%d) 2>/dev/null || true
PROPS="-Dkura.os.version=debian -Dkura.arch=aarch64 -Dtarget.device=aarch64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$K -Dkura.configuration=file:$K/framework/kura.properties -Dkura.custom.configuration=file:$K/user/kura_custom.properties -Ddpa.configuration=$K/packages/dpa.properties -Dlog4j.configurationFile=file:$K/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
cat > /etc/systemd/system/kura-native.service <<UNIT
[Unit]
Description=Eclipse Kura, GraalVM native image (Atomos, profilo core+REST+JNI+cloud)
Wants=dbus.service
After=dbus.service network.target
Conflicts=kura.service

[Service]
User=kurad
Group=kurad
Type=simple
WorkingDirectory=$K
ExecStartPre=/bin/mkdir -p /tmp/.kura
ExecStart=$N/bin/kura-native -Xmx256m -Datomos.lib.dir=$N -Djava.library.path=$N/lib $PROPS
Restart=on-failure
RestartSec=5
SuccessExitStatus=143
AmbientCapabilities=cap_dac_override cap_dac_read_search cap_net_bind_service cap_sys_boot cap_kill cap_sys_module cap_sys_time cap_sys_tty_config cap_syslog

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl disable kura-native >/dev/null 2>&1 || true
wait401() { local t0=$(awk '{print $1}' /proc/uptime); for i in $(seq 1 1200); do c=$(curl -sk -m 1 -o /dev/null -w '%{http_code}' https://127.0.0.1:443/services/session/v1/currentIdentity); [ "$c" = 401 ] && { awk -v a=$t0 -v b="$(awk '{print $1}' /proc/uptime)" 'BEGIN{printf "%.1f", b-a}'; return; }; sleep 0.2; done; echo NA; }
echo "### classic restart with the CRL fix"; : > /var/log/kura.log; systemctl restart kura; echo "classic REST 401 at $(wait401) s"; sleep 20
echo "  crl: $(ls -la $K/user/security/ | grep -E 'crl' | awk '{print $5, $9}' | tr '\n' ' ')"; echo "  errors: $(grep -c ' ERROR ' /var/log/kura.log)"; grep ' ERROR ' /var/log/kura.log | grep -v ClockService | cut -c25-160 | head -3
echo "### switch to native"; : > /var/log/kura.log; systemctl start kura-native; echo "native REST 401 at $(wait401) s (kura classic: $(systemctl is-active kura))"; sleep 60
P=$(pgrep -x kura-native); echo "  RSS@60s $(( $(awk '/VmRSS/{print $2}' /proc/$P/status)/1024 )) MB, threads $(awk '/Threads/{print $2}' /proc/$P/status), user $(stat -c %U /proc/$P), errors $(grep -c ' ERROR ' /var/log/kura.log)"; grep ' ERROR ' /var/log/kura.log | grep -v ClockService | cut -c25-160 | head -3
echo "  udev: $(grep -c 'LinuxUdevNative' /var/log/kura.log); https: $(ss -ltnp | grep -cE ':(443|4443) ')"
echo "### switch back to classic"; : > /var/log/kura.log; systemctl start kura; echo "classic REST 401 at $(wait401) s (kura-native: $(systemctl is-active kura-native))"
systemctl is-enabled kura kura-native 2>&1 | tr '\n' ' '; echo
echo "### done"
