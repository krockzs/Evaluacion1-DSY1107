#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_MONITORING_POSTBOOT_$(date +%Y%m%d_%H%M%S).txt"
INSTANCE="i-0e3af62685c90f028"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

command -v aws >/dev/null
command -v python3 >/dev/null
[[ -s "$PEM" ]] || { echo "ERROR: PEM no encontrada"; exit 1; }
chmod 600 "$PEM"
TMP=$(mktemp -d)
chmod 700 "$TMP"
CFG="$TMP/ssh_config"
trap 'rm -rf "$TMP"' EXIT
exec > >(tee "$REPORT") 2>&1
trap 'echo "CERTIFICACION_INCOMPLETA=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - CERTIFICACION REINICIO MONITORING"
echo "=========================================="
date

echo
echo "=== 1. VERIFICAR AWS ANTES DEL REINICIO ==="
aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids "$INSTANCE" i-09732ce35a9b0e22b \
  --output json > "$TMP/instances.json"

APP_IP=$(python3 - "$TMP/instances.json" <<'PY_AWS'
import json
import sys

with open(sys.argv[1],encoding="utf-8") as fh:
    data=json.load(fh)
inst={x["InstanceId"]:x for reservation in data["Reservations"]
      for x in reservation["Instances"]}
assert len(inst)==2, "Inventario AWS incompleto"
mon=inst["i-0e3af62685c90f028"]
app=inst["i-09732ce35a9b0e22b"]
assert mon["State"]["Name"]=="running"
assert app["State"]["Name"]=="running"
assert mon["VpcId"]=="vpc-0eaa5603256f0610f"
assert mon["PrivateIpAddress"]=="172.31.69.49"
assert "sg-04a36e10adc053871" in {
    group["GroupId"] for group in mon["SecurityGroups"]
}
assert app.get("PublicIpAddress")
print(app["PublicIpAddress"])
PY_AWS
)
echo "IDENTIDADES_AWS=OK"
echo "MONITORING_VERIFICADA=OK"

cat > "$CFG" <<EOF_SSH
Host app
 HostName $APP_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ConnectTimeout 8
 ServerAliveInterval 8
 ServerAliveCountMax 1
Host monitoring
 HostName 172.31.69.49
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 8
 ServerAliveInterval 8
 ServerAliveCountMax 1
EOF_SSH
chmod 600 "$CFG"

echo
echo "=== 2. PRECHECK SOLO MONITORING ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'PRECHECK'
set -Eeuo pipefail
TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
ACTUAL=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$ACTUAL" == "i-0e3af62685c90f028" ]]
[[ "$(systemctl is-active docker.service)" == "active" ]]
for name in dsy1107-prometheus dsy1107-grafana dsy1107-kafka-exporter; do
  [[ "$(sudo -n docker inspect -f '{{.State.Running}}' "$name")" == "true" ]]
done
curl -fsS -m 6 http://127.0.0.1:9090/-/ready >/dev/null
curl -fsS -m 6 http://127.0.0.1:3000/api/health >/dev/null
echo "SERVICIOS_PREBOOT=OK"
PRECHECK

BEFORE=$(ssh -n -F "$CFG" monitoring 'cat /proc/sys/kernel/random/boot_id')
[[ "$BEFORE" =~ ^[0-9a-f-]{36}$ ]] || {
  echo "ERROR: boot_id previo invalido"; exit 1;
}
echo "BOOT_ID_ANTES=$BEFORE"

echo
echo "=== 3. REINICIAR EXCLUSIVAMENTE EC2 MONITORING ==="
aws ec2 reboot-instances --profile pedidos360 --region us-east-1 \
  --instance-ids "$INSTANCE"
echo "REINICIO_AWS_SOLICITADO=OK"

echo
echo "=== 4. ESPERAR NUEVO BOOT_ID ==="
AFTER=""
for attempt in $(seq 1 90); do
  CANDIDATE=$(ssh -n -F "$CFG" -o ConnectionAttempts=1 \
    -o ConnectTimeout=6 monitoring \
    'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)
  if [[ "$CANDIDATE" =~ ^[0-9a-f-]{36}$ && "$CANDIDATE" != "$BEFORE" ]]; then
    AFTER="$CANDIDATE"
    break
  fi
  if (( attempt % 10 == 0 )); then
    echo "ESPERANDO_REINICIO_INTENTO=$attempt/90"
  fi
  sleep 4
done
[[ -n "$AFTER" ]] || {
  echo "ERROR: no se pudo demostrar nuevo arranque"; exit 1;
}
echo "BOOT_ID_DESPUES=$AFTER"
echo "REINICIO_REAL_DEMOSTRADO=OK"

echo
echo "=== 5. CERTIFICAR SERVICIOS POSTBOOT ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'POSTCHECK'
set -Eeuo pipefail
TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
ACTUAL=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$ACTUAL" == "i-0e3af62685c90f028" ]]
echo "IDENTIDAD_MONITORING_POSTBOOT=OK"

for unit in containerd.service docker.service; do
  [[ "$(systemctl is-active "$unit")" == "active" ]] || {
    echo "ERROR: servicio detenido: $unit"; exit 1;
  }
  [[ "$(systemctl is-enabled "$unit")" == "enabled" ]] || {
    echo "ERROR: servicio no habilitado: $unit"; exit 1;
  }
  echo "SYSTEMD_$unit=ACTIVE_ENABLED"
done

for name in dsy1107-prometheus dsy1107-grafana dsy1107-kafka-exporter; do
  running=$(sudo -n docker inspect -f '{{.State.Running}}' "$name")
  policy=$(sudo -n docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name")
  [[ "$running" == "true" && "$policy" == "unless-stopped" ]] || {
    echo "ERROR: contenedor no recuperado: $name"; exit 1;
  }
  echo "CONTENEDOR_POSTBOOT_$name=RUNNING"
done
echo "CONTENEDORES_POSTBOOT=OK"

echo
echo "--- Verificar Prometheus, Grafana y métricas reales ---"
python3 - <<'PY_VERIFY'
import base64
import http.client
import json
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request

password=Path(
    "/home/ubuntu/dsy1107-ep5/monitoring/secrets/grafana_password.txt"
).read_text(encoding="utf-8").strip()
assert len(password)>=32, "Secreto Grafana invalido"
auth=base64.b64encode(("admin:"+password).encode("utf-8")).decode("ascii")

def api(port,path,authenticated=False):
    headers={"Accept":"application/json"}
    if authenticated:
        headers["Authorization"]="Basic "+auth
    req=urllib.request.Request(
        "http://127.0.0.1:"+str(port)+path,headers=headers)
    with urllib.request.urlopen(req,timeout=7) as response:
        return json.load(response)

ready=False
for attempt in range(1,51):
    try:
        health=api(3000,"/api/health")
        assert health.get("database")=="ok"
        dashboard=api(
            3000,"/api/dashboards/uid/dsy1107-kafka-ep5",True)
        panels=dashboard.get("dashboard",{}).get("panels",[])
        assert len(panels)==15
        response=api(9090,"/api/v1/query?"+
                     urllib.parse.urlencode({"query":"kafka_brokers"}))
        values=[float(x["value"][1]) for x in
                response.get("data",{}).get("result",[])]
        assert response.get("status")=="success"
        assert values and max(values)>=2
        targets=api(9090,"/api/v1/targets")
        health_by_job={
            x.get("labels",{}).get("job"): x.get("health")
            for x in targets.get("data",{}).get("activeTargets",[])
        }
        assert health_by_job.get("prometheus")=="up"
        assert health_by_job.get("kafka-exporter")=="up"
        ready=True
        break
    except (urllib.error.HTTPError,urllib.error.URLError,
            http.client.RemoteDisconnected,ConnectionResetError,
            ConnectionRefusedError,TimeoutError,OSError,
            AssertionError,ValueError,KeyError) as exc:
        if attempt%10==0:
            print("ESPERANDO_METRICAS_POSTBOOT={}/50 MOTIVO={}".format(
                attempt,type(exc).__name__),flush=True)
        time.sleep(3)

if not ready:
    raise RuntimeError("APIs o metricas no recuperadas tras reinicio")
print("GRAFANA_PANELES_POSTBOOT=15")
print("GRAFANA_PROVISIONADO="+str(
    dashboard.get("meta",{}).get("provisioned",False)))
print("PROMETHEUS_TARGETS_POSTBOOT=UP")
print("KAFKA_BROKERS_POSTBOOT=2")
print("METRICAS_POSTBOOT=OK")
PY_VERIFY

echo
echo "--- Conectividad privada a brokers ---"
for ip in 172.31.91.91 172.31.27.158; do
  if timeout 6 bash -c "echo >/dev/tcp/$ip/9092" 2>/dev/null; then
    echo "KAFKA_$ip:9092=OPEN"
  else
    echo "ERROR: conexion Kafka perdida: $ip"; exit 1;
  fi
done

echo
echo "--- Contenedores y recursos ---"
sudo -n docker ps --format \
  'CONTENEDOR={{.Names}} ESTADO={{.Status}} PUERTOS={{.Ports}}'
free -h
df -h /
echo "MONITORING_POSTBOOT=OK"
POSTCHECK

echo
echo "=========================================="
echo " MONITORING CERTIFICADO TRAS REINICIO"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
