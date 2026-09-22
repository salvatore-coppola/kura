#!/bin/bash
# Host side: start a Mosquitto broker (plain 1883, TLS 8883 with a throwaway CA) for the MQTT check.
# usage: broker-up.sh <state dir> <net|host> [extra SAN IPs...]   (net = docker network kura-native-net, broker at 172.30.0.10)
set -u
D=$1; MODE=$2; shift 2; mkdir -p $D/certs $D/conf
if [ ! -f $D/certs/ca.crt ]; then
  SAN="DNS:mosq,DNS:localhost,IP:127.0.0.1,IP:172.30.0.10"; for ip in "$@"; do SAN="$SAN,IP:$ip"; done
  openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=kura-native-test-ca" -keyout $D/certs/ca.key -out $D/certs/ca.crt 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -subj "/CN=mosq" -keyout $D/certs/server.key -out $D/certs/server.csr 2>/dev/null
  openssl x509 -req -in $D/certs/server.csr -CA $D/certs/ca.crt -CAkey $D/certs/ca.key -CAcreateserial -days 30 -out $D/certs/server.crt -extfile <(printf "subjectAltName=%s\nextendedKeyUsage=serverAuth" "$SAN") 2>/dev/null
  chmod 644 $D/certs/*
fi
printf 'listener 1883\nallow_anonymous true\nlistener 8883\nallow_anonymous true\ncafile /certs/ca.crt\ncertfile /certs/server.crt\nkeyfile /certs/server.key\nlog_type all\n' > $D/conf/mosquitto.conf
docker rm -f kura-mosq >/dev/null 2>&1
if [ "$MODE" = net ]; then docker network inspect kura-native-net >/dev/null 2>&1 || docker network create --subnet 172.30.0.0/24 kura-native-net >/dev/null; NETOPT="--network kura-native-net --ip 172.30.0.10"; else NETOPT="--network host"; fi
docker run -d --name kura-mosq $NETOPT -v $D/conf/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro -v $D/certs:/certs:ro eclipse-mosquitto:2 >/dev/null
sleep 2; docker logs kura-mosq 2>&1 | grep -E "Opening|Error|error" | head -4
