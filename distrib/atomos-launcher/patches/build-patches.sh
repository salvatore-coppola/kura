#!/bin/bash
# Builds Atomos-compatibility patches of third-party bundles (single-classloader fallbacks). Output: patches/out/<jar>
set -e
cd "$(dirname "$0")"
ORIG=/home/scoppola/kura-native-bench/kura/plugins/2s/osgi-resource-locator-1.0.3.jar
OSGI=../target/lib/org.eclipse.osgi-3.21.0.jar
rm -rf out build && mkdir -p out build/orl
javac --release 21 -nowarn -cp "$ORIG:$OSGI" -d build/orl $(find osgi-resource-locator/src -name "*.java")
cp "$ORIG" out/osgi-resource-locator-1.0.3.jar
(cd build/orl && jar uf ../../out/osgi-resource-locator-1.0.3.jar org)
unzip -l out/osgi-resource-locator-1.0.3.jar | grep -c "class$"
