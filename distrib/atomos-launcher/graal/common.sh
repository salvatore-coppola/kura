# shared by the graal scripts, executed inside the kura-graal container (paths: /atomos = launcher target, /graal = this dir)
EXCLUDE_RE=$(cat /graal/profile-min.exclude)
build_cp() {
  CP=/atomos/org.eclipse.kura.atomos.launcher-6.0.0-SNAPSHOT.jar:/atomos/lib/org.apache.felix.atomos-1.0.0.jar:/opt/eclipse/kura/plugins/org.eclipse.osgi-3.21.0.jar
  for l in 1 1s 2 2s 3 3s 4 4s 5 5s 6 6s; do for j in /opt/eclipse/kura/plugins/$l/*.jar; do
    echo "$j" | grep -qE "$EXCLUDE_RE|osgi-resource-locator" && continue; CP=$CP:$j; done; done
  for j in /atomos/patches/*/*.jar; do echo "$j" | grep -q osgi-resource-locator && continue; CP=$CP:$j; done
  echo "$CP"
}
D=/opt/eclipse/kura
KURA_PROPS="-Dkura.os.version=debian -Dkura.arch=x86_64 -Dtarget.device=x86_64 -Dorg.eclipse.kura.core.crypto.secretKey= -Declipse.ignoreApp=true -Dkura.home=$D -Dkura.configuration=file:$D/framework/kura.properties -Dkura.custom.configuration=file:$D/user/kura_custom.properties -Ddpa.configuration=$D/packages/dpa.properties -Dlog4j.configurationFile=file:$D/log4j/log4j.xml -Dlog4j2.disable.jmx=true -Djdk.tls.trustNameService=true"
