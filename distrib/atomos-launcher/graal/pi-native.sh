#!/bin/bash
# On the device: build the GraalVM tool image, build the native image of the minimal profile, then run the A/B bench inside the container.
set -u
B=/root/kura-bench; W=$B/graal-work; mkdir -p $W/out $W/cfg
cd $B/graal && docker build -q -f Dockerfile.graal-pi -t kura-graal:21 . | tail -1
RUN="docker run --rm --privileged -v /opt/eclipse/kura:/opt/eclipse/kura:ro -v $B/atomos:/atomos:ro -v $B/graal:/graal:ro -v $W:/work kura-graal:21"
echo "### $(date -Is) native-image build"; time $RUN bash /graal/build-native.sh -J-Xmx5g > $W/build.log 2>&1; grep -E "Finished generating|Error|Caused by|in total|Peak RSS" $W/build.log | head -5
ls -la $W/out/
echo "### $(date -Is) smoke run"; $RUN bash /graal/run-native.sh 70 2>&1 | tail -12
echo "### $(date -Is) bench"; rm -f $W/bench-min.csv; $RUN bash /graal/bench.sh 3 120 2>&1 | tail -16
echo "### $(date -Is) pi native done"
