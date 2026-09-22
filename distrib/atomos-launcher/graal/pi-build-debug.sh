#!/bin/bash
# On the Pi: rebuild the JNI profile with thread-dump support and local symbols kept (for SIGQUIT stacks and gdb).
B=/root/kura-bench; W=$B/graal-work-jni; D=/opt/eclipse/kura
echo "### $(date -Is) debug build"
docker run --rm --privileged -e PROFILE=jni -e NATIVE_EXTRA_FLAGS="-H:+DumpThreadStacksOnSignal -H:-DeleteLocalSymbols" -v $D:$D:ro -v $B/atomos:/atomos:ro -v $B/graal:/graal:ro -v $W:/work kura-graal:21 bash /graal/build-native.sh -J-Xmx5g > $W/build-debug.log 2>&1
grep -E "Finished generating|Error|Caused by|Peak RSS" $W/build-debug.log | head -3
echo "### $(date -Is) debug build done"
