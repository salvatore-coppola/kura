#!/bin/bash
# Builds Atomos-compatibility patches of third-party bundles (single-classloader fallbacks). Output: patches/out/<jar>
set -e
cd "$(dirname "$0")"
ORIG=/home/scoppola/kura-native-bench/kura/plugins/2s/osgi-resource-locator-1.0.3.jar
OSGI=../target/lib/org.eclipse.osgi-3.21.0.jar
rm -rf out build && mkdir -p out/2s out/1s build/orl
javac --release 21 -nowarn -cp "$ORIG:$OSGI" -d build/orl $(find osgi-resource-locator/src -name "*.java")
cp "$ORIG" out/2s/osgi-resource-locator-1.0.3.jar
(cd build/orl && jar uf ../../out/2s/osgi-resource-locator-1.0.3.jar org)
SPIFLY=$(find ~/.m2/repository -name "org.apache.aries.spifly.static.bundle-1.3.7.jar" 2>/dev/null | head -1)
[ -n "$SPIFLY" ] || { mvn -q dependency:get -Dartifact=org.apache.aries.spifly:org.apache.aries.spifly.static.bundle:1.3.7 >/dev/null; SPIFLY=$(find ~/.m2/repository -name "org.apache.aries.spifly.static.bundle-1.3.7.jar" | head -1); }
cp "$SPIFLY" out/1s/
jar cfm out/1s/org.eclipse.kura.atomos.serviceloader.shim-1.0.0.jar serviceloader-shim/MANIFEST.MF
# osgitech REST whiteboard: deterministic proxy class names so GraalVM predefined classes match at run time
REST=/home/scoppola/kura-native-bench/kura/plugins/5s/org.eclipse.osgitech.rest-1.2.3.jar
mkdir -p out/5s build/rest
javac --release 21 -nowarn -proc:none -cp "$(ls /home/scoppola/kura-native-bench/kura/plugins/*/*.jar | tr '\n' ':')$OSGI" -d build/rest $(find osgitech-rest/src -name "*.java")
cp "$REST" out/5s/org.eclipse.osgitech.rest-1.2.3.jar
(cd build/rest && jar uf ../../out/5s/org.eclipse.osgitech.rest-1.2.3.jar org)
# equinox.io: drop the malformed org/osgi/service/io/package-info.class that makes native-image fail
EQIO=/home/scoppola/kura-native-bench/kura/plugins/1s/org.eclipse.equinox.io-1.1.300.jar
cp "$EQIO" out/1s/org.eclipse.equinox.io-1.1.300.jar && zip -q -d out/1s/org.eclipse.equinox.io-1.1.300.jar 'org/osgi/service/io/package-info.class' 'org/osgi/service/io/package-info.java' 2>/dev/null; unzip -l out/1s/org.eclipse.equinox.io-1.1.300.jar | grep -c package-info || true
# bundles with nested Bundle-ClassPath jars (Paho inside cloud.base.provider, protobuf inside the Kapua provider, usb4java): flatten them
bash flatten-nested.sh /home/scoppola/kura-native-bench/kura/plugins out org.eclipse.kura.cloud.base.provider org.eclipse.kura.cloudconnection.kapua.mqtt.provider org.usb4java usb4java-javax
find out -name "*.jar"
