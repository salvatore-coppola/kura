# shared by the graal scripts, executed inside the kura-graal container (paths: /atomos = launcher target, /graal = this dir)
PROFILE=${PROFILE:-min}
EXCLUDE_RE=$(cat /graal/profile-${PROFILE}.exclude)
build_cp() {
  CP=/atomos/org.eclipse.kura.atomos.launcher-6.0.0-SNAPSHOT.jar:/atomos/lib/org.apache.felix.atomos-1.0.0.jar:/opt/eclipse/kura/plugins/org.eclipse.osgi-3.21.0.jar
  PATCHED=$(ls /atomos/patches/*/*.jar 2>/dev/null | xargs -n1 basename | tr '\n' '|' | sed 's/|$//')
  for l in 1 1s 2 2s 3 3s 4 4s 5 5s 6 6s; do for j in /opt/eclipse/kura/plugins/$l/*.jar; do
    echo "$j" | grep -qE "$EXCLUDE_RE" && continue; [ -n "$PATCHED" ] && echo "$(basename $j)" | grep -qxE "$PATCHED" && continue; CP=$CP:$j; done; done
  for j in /atomos/patches/*/*.jar; do CP=$CP:$j; done
  echo "$CP"
}
D=/opt/eclipse/kura
ARCH=$(uname -m)
KURA_PROPS="-Dkura.os.version=debian -Dkura.arch=$ARCH -Dtarget.device=$ARCH -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
[ "$PROFILE" = jni ] && DIAG_OPTS="-Dkura.atomos.diag.comm=${DIAG_COMM:-/dev/ttyS0} -Dkura.atomos.diag.hid=true -Dkura.atomos.diag.filter=.*([Cc]loud|DataService|H2Db|Mqtt).*" || DIAG_OPTS=""
