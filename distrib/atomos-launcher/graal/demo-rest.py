#!/usr/bin/env python3
"""Kura REST demo: log in as admin and run a dozen authenticated calls, printing a readable outcome.

Usage: demo-rest.py [--url https://127.0.0.1] [--user admin] [--password PASSWORD] [--new-password NEW]
The password is taken, in order, from --password, the KURA_PASSWORD environment variable, the file given by
--password-file when it exists, and finally "admin". A gateway that still requires the first-login password
change needs --new-password. The printed report is in Italian on purpose: it is shown to the team.
"""

import argparse
import http.cookiejar
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

BOLD, DIM, GREEN, RED, YELLOW, RESET = "\033[1m", "\033[2m", "\033[32m", "\033[31m", "\033[33m", "\033[0m"


class Client:
    def __init__(self, base):
        self.base = base.rstrip("/")
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=context), urllib.request.HTTPCookieProcessor(self.jar))
        self.xsrf = None

    def call(self, method, path, body=None, timeout=30):
        url = f"{self.base}/services/{path}"
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        if data is not None:
            request.add_header("Content-Type", "application/json")
        if self.xsrf:
            request.add_header("X-XSRF-Token", self.xsrf)
        try:
            with self.opener.open(request, timeout=timeout) as response:
                return response.status, response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode("utf-8", "replace")
        except Exception as error:  # noqa: BLE001 - the demo must carry on and show the failure
            return 0, str(error)


def as_json(payload):
    try:
        return json.loads(payload)
    except ValueError:
        return None


def describe(label, payload):
    data = as_json(payload)
    if data is None:
        return (payload or "").strip()[:70]
    if label == "identity":
        return f"{data.get('name')}, permessi: {', '.join(data.get('permissions', []))}"
    if label == "properties":
        properties = data.get("kuraProperties", {})
        return (f"Kura {properties.get('kura.version', '?')} su {properties.get('kura.platform', '?')}, "
                f"home {properties.get('kura.home', '?')}")
    if label == "bundles":
        bundles = data.get("bundles", [])
        active = sum(1 for b in bundles if b.get("state") == "ACTIVE")
        signed = sum(1 for b in bundles if b.get("signed"))
        return f"{len(bundles)} bundle, {active} ACTIVE, {signed} firmati"
    if label == "packages":
        return f"{len(data.get('systemPackages', []))} pacchetti di sistema"
    if label == "dp":
        packages = data.get("deploymentPackages", [])
        return f"{len(packages)} deployment package" + (" (set di bundle chiuso)" if not packages else "")
    if label == "components":
        pids = data.get("pids", [])
        return f"{len(pids)} componenti configurabili, es. {pids[0] if pids else '-'}"
    if label == "snapshot":
        ids = data.get("ids", data.get("snapshots", []))
        return f"{len(ids)} snapshot elencati dal ConfigurationService"
    if label == "users":
        users = [u.get("userName") for u in data.get("userConfig", [])]
        return f"{len(users)} identita: {', '.join(users)}"
    if label == "permissions":
        permissions = data.get("permissions", [])
        return f"{len(permissions)} permessi definiti, es. {', '.join(permissions[:3])}"
    if label == "keystore":
        entries = data if isinstance(data, list) else []
        stores = sorted({e.get("keystoreServicePid") for e in entries})
        return f"{len(entries)} voci in {', '.join(stores) if stores else '-'}"
    if label == "cloud":
        instances = data.get("cloudEndpointInstances", [])
        if not instances:
            return "nessuna connessione cloud configurata"
        first = instances[0]
        return f"{len(instances)} endpoint, {first.get('cloudEndpointPid')} {first.get('state')}"
    if label == "connected":
        return "connesso al broker" if data.get("connected") else "non connesso al broker"
    if label == "login":
        return "sessione aperta" + (", richiesto il cambio password" if data.get("passwordChangeNeeded") else "")
    if label == "token":
        token = data.get("xsrfToken", "")
        return f"token {token[:8]}... per le chiamate successive"
    return json.dumps(data)[:70]


def runtime_banner():
    try:
        active = subprocess.run(["systemctl", "is-active", "kura-native", "kura"], capture_output=True, text=True,
                                timeout=5).stdout.split()
    except Exception:  # noqa: BLE001 - the banner is optional
        return ""
    if len(active) == 2 and active[0] == "active":
        return "runtime: immagine nativa GraalVM (kura-native.service)"
    if len(active) == 2 and active[1] == "active":
        return "runtime: JVM + Equinox (kura.service)"
    return ""


def main():
    parser = argparse.ArgumentParser(description="Kura REST demo")
    parser.add_argument("--url", default="https://127.0.0.1")
    parser.add_argument("--user", default="admin")
    parser.add_argument("--password", default=None)
    parser.add_argument("--password-file", default="/opt/eclipse/kura-native/demo-password")
    parser.add_argument("--new-password", default=None,
                        help="used when the gateway still requires the first-login password change")
    args = parser.parse_args()
    if args.password is None:
        args.password = os.environ.get("KURA_PASSWORD")
    if args.password is None and os.path.isfile(args.password_file):
        with open(args.password_file) as handle:
            args.password = handle.read().strip()
    if args.password is None:
        args.password = "admin"

    client = Client(args.url)
    print(f"{BOLD}Demo REST di Kura{RESET}  {args.url}/services")
    banner = runtime_banner()
    if banner:
        print(f"{DIM}{banner}{RESET}")
    print()

    steps, failures = [], 0
    started = time.monotonic()

    def step(number, title, method, path, label, body=None, expect=200, timeout=30):
        nonlocal failures
        begin = time.monotonic()
        code, payload = client.call(method, path, body, timeout=timeout)
        elapsed = time.monotonic() - begin
        ok = code == expect
        if not ok:
            failures += 1
        mark = f"{GREEN}OK{RESET}" if ok else f"{RED}KO{RESET}"
        detail = describe(label, payload) if ok else (payload or "nessuna risposta").strip()[:70]
        print(f" {number:2}  {title:<26} {method:<4} {path:<44} {code:>3} {mark} {elapsed:6.2f}s  {detail}")
        steps.append(ok)
        return payload

    payload = step(1, "login", "POST", "session/v1/login/password", "login",
                   {"username": args.user, "password": args.password})
    session = as_json(payload) or {}
    if session.get("passwordChangeNeeded"):
        if not args.new_password:
            print(f"\n{YELLOW}Il gateway chiede il cambio password al primo accesso: rilancia con "
                  f"--new-password <nuova>.{RESET}")
            return 2
        token = as_json(client.call("GET", "session/v1/xsrfToken")[1]) or {}
        client.xsrf = token.get("xsrfToken")
        client.call("POST", "session/v1/changePassword", {"currentPassword": args.password,
                                                          "newPassword": args.new_password})
        print(f"{DIM}     password aggiornata al primo accesso, nuovo login{RESET}")
        client.xsrf = None
        client.call("POST", "session/v1/login/password", {"username": args.user, "password": args.new_password})

    payload = step(2, "token anti-CSRF", "GET", "session/v1/xsrfToken", "token")
    client.xsrf = (as_json(payload) or {}).get("xsrfToken")

    step(3, "identita' corrente", "GET", "session/v1/currentIdentity", "identity")
    step(4, "proprieta' del sistema", "GET", "system/v1/properties/kura", "properties")
    step(5, "inventario bundle", "GET", "inventory/v1/bundles", "bundles", timeout=180)
    step(6, "inventario, gia' in cache", "GET", "inventory/v1/bundles", "bundles")
    step(7, "pacchetti di sistema", "GET", "inventory/v1/systemPackages", "packages")
    step(8, "deployment package", "GET", "inventory/v1/deploymentPackages", "dp")
    step(9, "componenti configurabili", "GET", "configuration/v2/configurableComponents", "components")
    step(10, "snapshot", "GET", "configuration/v2/snapshots", "snapshot")
    step(11, "identita' definite", "GET", "identity/v1/identities", "users")
    step(12, "permessi REST", "GET", "identity/v1/definedPermissions", "permissions")
    step(13, "chiavi e certificati", "GET", "keystores/v2/entries", "keystore")
    step(14, "connessioni cloud", "GET", "cloudconnection/v1/instances", "cloud")
    step(15, "stato connessione MQTT", "POST", "cloudconnection/v1/cloudEndpoint/isConnected", "connected",
         {"cloudEndpointPid": "org.eclipse.kura.cloud.CloudService"})
    step(16, "logout", "POST", "session/v1/logout", "raw", expect=204)
    client.xsrf = None
    step(17, "sessione chiusa (atteso 401)", "GET", "session/v1/currentIdentity", "raw", expect=401)
    print(f"{DIM}     la chiamata 5 verifica la firma dei jar dei bundle: e' il costo della prima volta, "
          f"poi la risposta e' in cache{RESET}")

    elapsed = time.monotonic() - started
    colour = GREEN if failures == 0 else RED
    print(f"\n{colour}{len(steps) - failures}/{len(steps)} chiamate con l'esito atteso{RESET} in {elapsed:.1f} s")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
