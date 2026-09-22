#!/bin/bash
# Inside kura-graal: build the native image of the minimal profile using the agent-generated configuration.
set -u
. /graal/common.sh
CP=$(build_cp)
mkdir -p /work/out
time native-image --no-fallback -H:+ReportExceptionStackTraces -H:ConfigurationFileDirectories=/work/cfg,/graal/extra-config \
  --enable-url-protocols=http,https -H:+UnlockExperimentalVMOptions ${NATIVE_EXTRA_FLAGS:-} "$@" \
  -cp "$CP" -o /work/out/kura-native org.eclipse.kura.atomos.KuraAtomosLauncher 2>&1 | tail -40
ls -la /work/out/
