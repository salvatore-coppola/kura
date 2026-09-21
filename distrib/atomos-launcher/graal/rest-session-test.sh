#!/bin/bash
# Inside the container: login, fetch the XSRF token and call authenticated endpoints. usage: rest-session-test.sh [base-url]
B=${1:-https://127.0.0.1:443/services}; C=/tmp/rest-cookies.txt; rm -f $C
code=$(curl -sk -m 10 -c $C -X POST -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}' -o /tmp/login.json -w '%{http_code}' "$B/session/v1/login/password")
echo "login: $code $(head -c 160 /tmp/login.json | tr -d '\n')"
echo "cookies: $(grep -E 'JSESSIONID' $C | awk '{print $6"="substr($7,1,12)"..."}' | tr '\n' ' ')"
code=$(curl -sk -m 10 -b $C -c $C -o /tmp/xsrf.json -w '%{http_code}' "$B/session/v1/xsrfToken")
X=$(grep -oE '"xsrfToken":"[^"]+"' /tmp/xsrf.json | cut -d'"' -f4); echo "xsrfToken: $code ${X:0:12}..."
if grep -q '"passwordChangeNeeded":true' /tmp/login.json; then
  code=$(curl -sk -m 10 -b $C -c $C -H "X-XSRF-Token: $X" -X POST -H 'Content-Type: application/json' -d '{"currentPassword":"admin","newPassword":"KuraNative!2026"}' -o /tmp/chg.json -w '%{http_code}' "$B/session/v1/changePassword")
  echo "changePassword: $code $(head -c 120 /tmp/chg.json | tr -d '\n')"
  code=$(curl -sk -m 10 -c $C -X POST -H 'Content-Type: application/json' -d '{"username":"admin","password":"KuraNative!2026"}' -o /tmp/login.json -w '%{http_code}' "$B/session/v1/login/password")
  echo "re-login: $code $(head -c 120 /tmp/login.json | tr -d '\n')"
  code=$(curl -sk -m 10 -b $C -c $C -o /tmp/xsrf.json -w '%{http_code}' "$B/session/v1/xsrfToken"); X=$(grep -oE '"xsrfToken":"[^"]+"' /tmp/xsrf.json | cut -d'"' -f4); echo "xsrfToken: $code ${X:0:12}..."
fi
for p in session/v1/currentIdentity inventory/v1/bundles system/v1/properties/kura identity/v1/identities configuration/v2/configurableComponents keystores/v2/entries; do
  code=$(curl -sk -m 15 -b $C -H "X-XSRF-Token: $X" -o /tmp/r.json -w '%{http_code}' "$B/$p"); echo "GET $p: $code $(head -c 100 /tmp/r.json | tr -d '\n')"
done
code=$(curl -sk -m 10 -b $C -H "X-XSRF-Token: $X" -X POST -o /dev/null -w '%{http_code}' "$B/session/v1/logout"); echo "logout: $code"
