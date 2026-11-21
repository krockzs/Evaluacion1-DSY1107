#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_MONITORING_METRICAS_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

command -v aws >/dev/null
[[ -s "$PEM" ]] || { echo "ERROR: clave PEM no encontrada"; exit 1; }
chmod 600 "$PEM"

CFG=$(mktemp)
chmod 600 "$CFG"
trap 'rm -f "$CFG"' EXIT

exec > >(tee "$REPORT") 2>&1
trap 'echo "AUDITORIA_INCOMPLETA=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - AUDITORIA METRICAS MONITORING"
echo "=========================================="
date

echo
echo "=== 1. VERIFICAR DIRECCIONES AWS ==="
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
  echo "ERROR: IP de Monitoring inesperada"; exit 1;
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
echo "=== 2. AUDITAR EC2 MONITORING SIN MODIFICACIONES ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'MON_AUDIT'
set -Eeuo pipefail

TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
INSTANCE=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$INSTANCE" == "i-0e3af62685c90f028" ]] || {
  echo "ERROR: EC2 no coincide"; exit 1;
}
echo "IDENTIDAD_MONITORING=OK"

echo
echo "--- Salud de contenedores ---"
for name in dsy1107-prometheus dsy1107-grafana dsy1107-kafka-exporter; do
  state=$(sudo -n docker inspect -f '{{.State.Status}}' "$name")
  echo "CONTENEDOR_$name=$state"
  [[ "$state" == "running" ]] || {
    echo "ERROR: contenedor no esta activo"; exit 1;
  }
done

echo
echo "--- APIs de Prometheus y Grafana ---"
for item in '9090:/-/ready' '3000:/api/health'; do
  port=$(printf '%s' "$item" | cut -d: -f1)
  endpoint=$(printf '%s' "$item" | cut -d: -f2-)
  status=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$port$endpoint" || true)
  echo "HTTP_$port=$status"
  [[ "$status" == "200" ]] || {
    echo "ERROR: API local no disponible"; exit 1;
  }
done

echo
echo "--- Target y series recopiladas ---"
python3 - <<'PY_METRICS'
import json
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:9090"
EXPECTED_JOBS = {"prometheus", "kafka-exporter"}
PREFIX = "kafka_"
KEY_METRICS = [
    "kafka_brokers",
    "kafka_topic_partitions",
    "kafka_topic_partition_current_offset",
    "kafka_topic_partition_leader",
    "kafka_topic_partition_replicas",
    "kafka_topic_partition_in_sync_replica",
    "kafka_topic_partition_under_replicated_partition",
    "kafka_consumergroup_current_offset",
    "kafka_consumergroup_lag",
]

def get(path, params=None):
    suffix = ("?" + urllib.parse.urlencode(params)) if params else ""
    url = BASE + path + suffix
    with urllib.request.urlopen(url, timeout=15) as res:
        payload = json.load(res)
    if payload.get("status") != "success":
        raise RuntimeError("API Prometheus: respuesta no exitosa")
    return payload["data"]

targets = get("/api/v1/targets")
active = targets.get("activeTargets", [])
jobs = {}
for item in active:
    name = item.get("labels", {}).get("job", "")
    jobs.setdefault(name, []).append(item)
    print("TARGET_JOB={0} HEALTH={1} SCRAPE={2}".format(
        name,
        item.get("health", "unknown"),
        item.get("scrapeUrl", "N/A"),
    ))
    if item.get("lastError"):
        print("TARGET_ERROR={0}".format(str(item["lastError"])[:240]))
for name in sorted(EXPECTED_JOBS):
    if name not in jobs or not any(x.get("health") == "up" for x in jobs[name]):
        raise RuntimeError("Prometheus: target sin estado UP: " + name)
print("PROMETHEUS_TARGETS=UP")

names = get("/api/v1/label/__name__/values")
kafka_names = sorted(x for x in names if x.startswith(PREFIX))
print("TOTAL_METRICAS_KAFKA={0}".format(len(kafka_names)))
for name in kafka_names:
    print("METRICA_DISPONIBLE=" + name)

print("")
print("--- Metricas relevantes para dashboards ---")
for name in KEY_METRICS:
    if name not in kafka_names:
        print("METRICA_{0}=AUSENTE".format(name))
        continue
    records = get("/api/v1/query", {"query": name}).get("result", [])
    print("METRICA_{0}=PRESENTE SERIES={1}".format(name, len(records)))
    if name == "kafka_brokers":
        values = [float(x["value"][1]) for x in records]
        count = max(values) if values else 0
        print("BROKERS_REALES={0}".format(count))
        if count < 2:
            raise RuntimeError("Kafka Exporter no detecta 2 brokers")
    if name in ("kafka_consumergroup_lag", "kafka_topic_partitions"):
        for record in records[:6]:
            labels = record.get("metric", {})
            selected = {
                key: value
                for key, value in labels.items()
                if key in ("consumergroup", "topic", "partition", "job")
            }
            print("SERIE_EJEMPLO={0} VALOR={1}".format(
                json.dumps(selected, ensure_ascii=False, sort_keys=True),
                record["value"][1],
            ))

if "kafka_brokers" not in kafka_names:
    raise RuntimeError("Falta la metrica principal kafka_brokers")

print("METRICAS_AUDITADAS=OK")
PY_METRICS

echo
echo "--- Seguridad y recursos finales ---"
sudo -n docker ps --format \
  'CONTENEDOR={{.Names}} ESTADO={{.Status}} PUERTOS={{.Ports}}'
free -h
df -h /
echo "AUDITORIA_MONITORING=OK"
MON_AUDIT

echo
echo "=========================================="
echo " INVENTARIO DE METRICAS COMPLETADO"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
