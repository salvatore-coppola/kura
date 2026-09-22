#!/bin/bash
# Inside the container: point the default MqttDataTransport at a broker through REST, connect the cloud endpoint and report the state.
# usage: mqtt-test.sh <broker-url> [ca-pem-file] [base-url]
BROKER=$1; CA=${2:-}; B=${3:-https://127.0.0.1:443/services}; C=/tmp/mqtt-cookies.txt; rm -f $C
PID_TRANSPORT=org.eclipse.kura.core.data.transport.mqtt.MqttDataTransport; PID_ENDPOINT=${MQTT_ENDPOINT_PID:-org.eclipse.kura.cloud.CloudService}
login() { curl -sk -m 10 -c $C -X POST -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"$1\"}" -o /tmp/mlogin.json -w '%{http_code}' "$B/session/v1/login/password"; }
code=$(login 'KuraNative!2026'); [ "$code" = 200 ] || code=$(login admin); echo "mqtt-test login: $code"
X=$(curl -sk -m 10 -b $C -c $C "$B/session/v1/xsrfToken" | grep -oE '"xsrfToken":"[^"]+"' | cut -d'"' -f4)
H=(-sk -m 20 -b $C -H "X-XSRF-Token: $X" -H 'Content-Type: application/json')
echo "instances: $(curl "${H[@]}" "$B/cloudconnection/v1/instances" | head -c 300)"
if [ -n "$CA" ]; then
  PEM=$(awk '{printf "%s\\n",$0}' "$CA")
  code=$(curl "${H[@]}" -X POST -d "{\"keystoreServicePid\":\"SSLKeystore\",\"alias\":\"mqtt-test-ca\",\"certificate\":\"$PEM\"}" -o /tmp/ca.json -w '%{http_code}' "$B/keystores/v1/entries/certificate")
  echo "add CA to SSLKeystore: $code $(head -c 120 /tmp/ca.json | tr -d '\n')"
fi
code=$(curl "${H[@]}" -X PUT -d "{\"configs\":[{\"pid\":\"$PID_TRANSPORT\",\"properties\":{\"broker-url\":{\"type\":\"STRING\",\"value\":\"$BROKER\"}}}],\"takeSnapshot\":false}" -o /tmp/upd.json -w '%{http_code}' "$B/configuration/v2/configurableComponents/configurations/_update")
echo "set broker-url=$BROKER: $code $(head -c 120 /tmp/upd.json | tr -d '\n')"; sleep 2
code=$(curl "${H[@]}" -X POST -d "{\"cloudEndpointPid\":\"$PID_ENDPOINT\"}" -o /tmp/conn.json -w '%{http_code}' "$B/cloudconnection/v1/cloudEndpoint/connect")
echo "connect: $code $(head -c 200 /tmp/conn.json | tr -d '\n')"
st=; for i in $(seq 1 30); do st=$(curl "${H[@]}" -X POST -d "{\"cloudEndpointPid\":\"$PID_ENDPOINT\"}" "$B/cloudconnection/v1/cloudEndpoint/isConnected"); echo "$st" | grep -q '"connected":true' && break; sleep 1; done
echo "isConnected after ${i} s: $st"
curl "${H[@]}" -X POST -d "{\"cloudEndpointPid\":\"$PID_ENDPOINT\"}" -o /dev/null -w 'disconnect: %{http_code}\n' "$B/cloudconnection/v1/cloudEndpoint/disconnect"
curl -sk -m 10 -b $C -H "X-XSRF-Token: $X" -X POST -o /dev/null -w 'logout: %{http_code}\n' "$B/session/v1/logout"
