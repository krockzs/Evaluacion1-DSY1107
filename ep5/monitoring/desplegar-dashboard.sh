#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/PROYECTOS/DUOC/Evaluacion1-DSY1107"
BASE="$ROOT/ep5/monitoring"
PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_GRAFANA_DASHBOARD_$(date +%Y%m%d_%H%M%S).txt"
REMOTE="/home/ubuntu/dsy1107-ep5/monitoring"
PROVIDER="grafana/provisioning/dashboards/default.yaml"
DASH="grafana/dashboards/dsy1107-kafka-ep5.json"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

command -v aws >/dev/null
command -v python3 >/dev/null
[[ -s "$PEM" ]] || { echo "ERROR: falta PEM"; exit 1; }
for relative in compose.yaml "$PROVIDER" "$DASH"; do
  [[ -s "$BASE/$relative" ]] || {
    echo "ERROR: archivo versionado no encontrado: $relative"; exit 1;
  }
done
python3 -m json.tool "$BASE/$DASH" >/dev/null
chmod 600 "$PEM"

CFG=$(mktemp)
chmod 600 "$CFG"
trap 'rm -f "$CFG"' EXIT

exec > >(tee "$REPORT") 2>&1
trap 'echo "DASHBOARD_DESPLIEGUE_INCOMPLETO=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - DASHBOARD GRAFANA KAFKA EP5"
echo "=========================================="
date

echo
echo "=== 1. VALIDAR ARCHIVOS Y DIRECCIONES AWS ==="
python3 - "$BASE/$DASH" <<'PY_LOCAL'
import json
import sys
with open(sys.argv[1],encoding="utf-8") as handle:
    obj=json.load(handle)
assert obj.get("uid")=="dsy1107-kafka-ep5", "UID incorrecto"
assert len(obj.get("panels",[]))==15, "Cantidad de paneles distinta"
ids=[p["id"] for p in obj["panels"]]
assert len(ids)==len(set(ids)), "IDs de paneles repetidos"
print("DASHBOARD_JSON=OK")
print("PANELES_VERSIONADOS="+str(len(ids)))
PY_LOCAL

APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
MON_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-0e3af62685c90f028 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != "None" ]] || {
  echo "ERROR: APP sin IP publica"; exit 1;
}
[[ "$MON_IP" == "172.31.69.49" ]] || {
  echo "ERROR: IP Monitoring inesperada"; exit 1;
}

cat > "$CFG" <<EOF_SSH
Host app
 HostName $APP_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ConnectTimeout 15
Host monitoring
 HostName $MON_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
EOF_SSH

echo
echo "=== 2. VALIDAR DESTINO Y CREAR CARPETAS ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_PREP'
set -Eeuo pipefail
TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
INSTANCE=$(curl -fsS -m 5 \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$INSTANCE" == "i-0e3af62685c90f028" ]] || {
  echo "ERROR: instancia equivocada"; exit 1;
}
cd /home/ubuntu/dsy1107-ep5/monitoring
[[ -s compose.yaml ]] || { echo "ERROR: Compose no encontrado"; exit 1; }
[[ -s secrets/grafana_password.txt ]] || {
  echo "ERROR: secreto Grafana ausente"; exit 1;
}
sudo -n docker inspect dsy1107-grafana >/dev/null
sudo -n docker inspect dsy1107-prometheus >/dev/null
sudo -n docker inspect dsy1107-kafka-exporter >/dev/null
install -d -m 0755 grafana/provisioning/dashboards
install -d -m 0755 grafana/dashboards
echo "IDENTIDAD_MONITORING=OK"
echo "SECRETO_GRAFANA=REUTILIZADO_SIN_MOSTRAR"
echo "DIRECTORIOS_GRAFANA=OK"
REMOTE_PREP

echo
echo "=== 3. TRANSFERIR SOLO CONFIGURACION DE DASHBOARD ==="
scp -q -F "$CFG" "$BASE/compose.yaml" \
  "monitoring:$REMOTE/compose.yaml" </dev/null
scp -q -F "$CFG" "$BASE/$PROVIDER" \
  "monitoring:$REMOTE/$PROVIDER" </dev/null
scp -q -F "$CFG" "$BASE/$DASH" \
  "monitoring:$REMOTE/$DASH" </dev/null
echo "ARCHIVOS_DASHBOARD_TRANSFERIDOS=OK"

echo
echo "=== 4. RECREAR SOLO GRAFANA Y VERIFICAR API ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_DEPLOY'
set -Eeuo pipefail
cd /home/ubuntu/dsy1107-ep5/monitoring

sudo -n docker compose -f compose.yaml config --quiet
echo "COMPOSE_CONFIG=OK"
sudo -n docker compose -f compose.yaml up -d \
  --no-deps --force-recreate grafana
echo "SOLO_GRAFANA_RECREADA=OK"

python3 - <<'PY_GRAFANA'
import base64
import http.client
import json
import pathlib
import time
import urllib.error
import urllib.request

secret_path=pathlib.Path(
    "/home/ubuntu/dsy1107-ep5/monitoring/secrets/grafana_password.txt")
password=secret_path.read_text(encoding="utf-8").strip()
assert len(password)>=32, "Contraseña Grafana no valida"
auth=base64.b64encode(("admin:"+password).encode("utf-8")).decode("ascii")
endpoint="http://127.0.0.1:3000/api/dashboards/uid/dsy1107-kafka-ep5"
ds_endpoint="http://127.0.0.1:3000/api/datasources/uid/dsy1107-prometheus"

def fetch(url):
    request=urllib.request.Request(
        url,
        headers={"Authorization": "Basic "+auth, "Accept": "application/json"}
    )
    with urllib.request.urlopen(request,timeout=5) as response:
        return json.load(response)

loaded=None
for attempt in range(1,31):
    try:
        loaded=fetch(endpoint)
        break
    except (urllib.error.HTTPError, urllib.error.URLError,
            http.client.RemoteDisconnected, ConnectionResetError,
            ConnectionAbortedError, ConnectionRefusedError,
            TimeoutError, OSError):
        if attempt%5==0:
            print("ESPERANDO_GRAFANA_PANEL_INTENTO={}/30".format(attempt))
        time.sleep(2)
if loaded is None:
    raise RuntimeError("No se puede consultar dashboard por API Grafana")

dashboard=loaded.get("dashboard",{})
assert dashboard.get("uid")=="dsy1107-kafka-ep5", \
    "Grafana no devolvio el dashboard esperado"
panels=dashboard.get("panels",[])
assert len(panels)==15, \
    "Se esperaban 15 paneles; se obtuvieron {}".format(len(panels))
print("GRAFANA_DASHBOARD_UID="+dashboard["uid"])
print("GRAFANA_PANELES_CARGADOS="+str(len(panels)))
print("GRAFANA_PANEL_URL=/d/dsy1107-kafka-ep5")

ds=fetch(ds_endpoint)
assert ds.get("uid")=="dsy1107-prometheus", \
    "Datasource Grafana no corresponde"
print("GRAFANA_DATASOURCE=OK")
print("GRAFANA_API_DASHBOARD=OK")
PY_GRAFANA

echo
echo "=== 5. VALIDAR PROMQL CONTRA METRICAS REALES ==="
python3 - <<'PY_QUERIES'
import json
import pathlib
import urllib.parse
import urllib.request

base=pathlib.Path("/home/ubuntu/dsy1107-ep5/monitoring")
dashboard=json.loads(
    (base/"grafana/dashboards/dsy1107-kafka-ep5.json").read_text(
        encoding="utf-8"))
valid=0
no_data=[]
for panel in dashboard["panels"]:
    if panel["type"]=="text":
        continue
    for target in panel.get("targets",[]):
        expr=target["expr"]
        url="http://127.0.0.1:9090/api/v1/query?" + \
            urllib.parse.urlencode({"query":expr})
        with urllib.request.urlopen(url,timeout=12) as response:
            payload=json.load(response)
        assert payload.get("status")=="success", \
            "PromQL invalido en panel {}".format(panel["id"])
        rows=payload.get("data",{}).get("result",[])
        if not rows:
            no_data.append(panel["id"])
        valid+=1
print("PROMQL_CONSULTAS_VALIDAS="+str(valid))
print("PANELES_CON_DATOS_AUN_NO_DISPONIBLES="+(
    ",".join(str(x) for x in sorted(set(no_data))) if no_data else "NINGUNO"))
print("PROMQL_VALIDADO=OK")
PY_QUERIES

echo
echo "=== 6. COMPROBAR CONTENEDORES Y PUERTOS ==="
for service in dsy1107-grafana dsy1107-prometheus dsy1107-kafka-exporter; do
  running=$(sudo -n docker inspect -f '{{.State.Running}}' "$service")
  policy=$(sudo -n docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$service")
  echo "CONTENEDOR_$service=$running RESTART_POLICY=$policy"
  [[ "$running" == "true" && "$policy" == "unless-stopped" ]] || {
    echo "ERROR: contenedor inesperado $service"; exit 1;
  }
done
sudo -n docker ps --format \
  'CONTENEDOR={{.Names}} PUERTOS={{.Ports}}'

curl -fsS --max-time 6 \
  http://127.0.0.1:3000/api/health >/dev/null
curl -fsS --max-time 6 \
  http://127.0.0.1:9090/-/ready >/dev/null
echo "GRAFANA_HTTP=OK"
echo "PROMETHEUS_HTTP=OK"

echo "MONITORING_DASHBOARD=OK"
REMOTE_DEPLOY

echo
echo "=========================================="
echo " DASHBOARD GRAFANA LISTO PARA VISUALIZAR"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
