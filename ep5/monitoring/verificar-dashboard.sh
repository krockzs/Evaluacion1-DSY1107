#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_GRAFANA_VERIFICACION_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

command -v aws >/dev/null
[[ -s "$PEM" ]] || { echo "ERROR: PEM ausente"; exit 1; }
chmod 600 "$PEM"
CFG=$(mktemp)
chmod 600 "$CFG"
trap 'rm -f "$CFG"' EXIT
exec > >(tee "$REPORT") 2>&1
trap 'echo "VERIFICACION_INCOMPLETA=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - VERIFICAR DASHBOARD SIN CAMBIOS"
echo "=========================================="
date

echo
echo "=== 1. OBTENER DIRECCIONES AWS ==="
APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
MON_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-0e3af62685c90f028 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != "None" ]] || { echo "ERROR: APP sin IP"; exit 1; }
[[ "$MON_IP" == "172.31.69.49" ]] || { echo "ERROR: IP Monitoring inesperada"; exit 1; }

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
echo "=== 2. VERIFICAR CONTENEDORES Y DASHBOARD ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_VERIFY'
set -Eeuo pipefail

TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
INSTANCE=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$INSTANCE" == "i-0e3af62685c90f028" ]] || {
  echo "ERROR: instancia Monitoring incorrecta"; exit 1;
}
echo "IDENTIDAD_MONITORING=OK"

echo
echo "--- Contenedores y contadores de reinicio ---"
for name in dsy1107-grafana dsy1107-prometheus dsy1107-kafka-exporter; do
  sudo -n docker inspect --format \
    'CONTENEDOR={{.Name}} ESTADO={{.State.Status}} RESTARTS={{.RestartCount}} RESTART_POLICY={{.HostConfig.RestartPolicy.Name}}' "$name"
done
echo
echo "--- Comprobacion de archivos de dashboard ---"
cd /home/ubuntu/dsy1107-ep5/monitoring
for path in \
  grafana/dashboards/dsy1107-kafka-ep5.json \
  grafana/provisioning/dashboards/default.yaml \
  grafana/provisioning/datasources/prometheus.yaml; do
  [[ -s "$path" ]] || { echo "ERROR: archivo ausente: $path"; exit 1; }
  echo "ARCHIVO_PRESENTE=$path"
done

echo
echo "--- API autenticada de Grafana y consultas PromQL ---"
if python3 - <<'PY_API'
import base64
import http.client
import json
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

BASE=pathlib.Path("/home/ubuntu/dsy1107-ep5/monitoring")
PASSWORD=(BASE/"secrets/grafana_password.txt").read_text(encoding="utf-8").strip()
if len(PASSWORD)<32:
    raise RuntimeError("El secreto de Grafana no cumple longitud minima")
AUTH=base64.b64encode(("admin:"+PASSWORD).encode("utf-8")).decode("ascii")
ENDPOINT="http://127.0.0.1:3000"

def api(path, authenticated=False, timeout=6):
    headers={"Accept": "application/json"}
    if authenticated:
        headers["Authorization"]="Basic "+AUTH
    request=urllib.request.Request(ENDPOINT+path,headers=headers)
    with urllib.request.urlopen(request,timeout=timeout) as response:
        return json.load(response)

dash=None
for attempt in range(1,31):
    try:
        health=api("/api/health")
        if health.get("database")!="ok":
            raise RuntimeError("Grafana: base de datos no disponible")
        dash=api("/api/dashboards/uid/dsy1107-kafka-ep5",True)
        break
    except urllib.error.HTTPError as exc:
        if exc.code in (401,403):
            raise RuntimeError("Credenciales de API Grafana rechazadas: HTTP "+str(exc.code))
        if attempt%5==0:
            print("REINTENTO_GRAFANA={}/30 HTTP={}".format(attempt,exc.code))
    except (urllib.error.URLError,http.client.RemoteDisconnected,
            ConnectionResetError,ConnectionAbortedError,
            ConnectionRefusedError,TimeoutError,OSError) as exc:
        if attempt%5==0:
            print("REINTENTO_GRAFANA={}/30 MOTIVO={}".format(
                attempt,type(exc).__name__))
    time.sleep(2)
if dash is None:
    raise RuntimeError("Dashboard no disponible tras reintentos")

obj=dash.get("dashboard",{})
assert obj.get("uid")=="dsy1107-kafka-ep5", "UID incorrecto"
assert len(obj.get("panels",[]))==15, "No aparecen los 15 paneles"
print("GRAFANA_SALUD=OK")
print("GRAFANA_DASHBOARD_UID="+obj["uid"])
print("GRAFANA_PANELES_CARGADOS="+str(len(obj["panels"])))
print("GRAFANA_PROVISIONADO="+str(dash.get("meta",{}).get("provisioned","desconocido")))

datasource=api("/api/datasources/uid/dsy1107-prometheus",True)
assert datasource.get("uid")=="dsy1107-prometheus", "Datasource incorrecto"
print("GRAFANA_DATASOURCE=OK")
print("GRAFANA_PANEL_RUTA=/d/dsy1107-kafka-ep5")

def promql(expr):
    url="http://127.0.0.1:9090/api/v1/query?"+urllib.parse.urlencode({"query":expr})
    with urllib.request.urlopen(url,timeout=12) as response:
        payload=json.load(response)
    if payload.get("status")!="success":
        raise RuntimeError("PromQL no valida")
    return payload.get("data",{}).get("result",[])

count=0
empty=[]
for panel in obj.get("panels",[]):
    for target in panel.get("targets",[]):
        rows=promql(target["expr"])
        count+=1
        if not rows:
            empty.append(str(panel["id"]))
print("PROMQL_CONSULTAS_VALIDAS="+str(count))
print("PANELES_CON_SERIES_AUSENTES="+(
    ",".join(sorted(set(empty))) if empty else "NINGUNO"))
brokers=promql("kafka_brokers")
if not brokers or max(float(r["value"][1]) for r in brokers)<2:
    raise RuntimeError("Kafka Exporter no demuestra 2 brokers")
print("KAFKA_BROKERS=2")
print("VERIFICACION_DASHBOARD=OK")
PY_API
then
  echo "GRAFANA_API=OK"
else
  echo "GRAFANA_API=ERROR"
  echo "--- Ultimas lineas de Grafana relacionadas con arranque/provisioning ---"
  sudo -n docker logs --tail 110 dsy1107-grafana 2>&1 |
    grep -Ei 'level=error|level=warn|provision|dashboard|fail|error' |
    tail -45 | cut -c1-280 || true
  exit 1
fi

echo
echo "--- Estado de servicios locales ---"
curl -fsS --max-time 6 http://127.0.0.1:9090/-/ready >/dev/null
curl -fsS --max-time 6 http://127.0.0.1:3000/api/health >/dev/null
echo "PROMETHEUS_HTTP=OK"
echo "GRAFANA_HTTP=OK"
echo "MONITORING_SIN_CAMBIOS=OK"
REMOTE_VERIFY

echo
echo "=========================================="
echo " DASHBOARD VALIDADO SIN RECREAR SERVICIOS"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
