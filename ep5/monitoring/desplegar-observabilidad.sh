#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/PROYECTOS/DUOC/Evaluacion1-DSY1107"
BASE="$ROOT/ep5/monitoring"
PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_MONITORING_DESPLIEGUE_$(date +%Y%m%d_%H%M%S).txt"
REMOTE_BASE="/home/ubuntu/dsy1107-ep5/monitoring"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

[[ -s "$PEM" ]] || { echo "ERROR: no existe el PEM"; exit 1; }
command -v aws >/dev/null
[[ -f "$BASE/compose.yaml" ]] || { echo "ERROR: Compose no disponible"; exit 1; }
[[ -f "$BASE/prometheus/prometheus.yml" ]] || { echo "ERROR: Prometheus YAML no disponible"; exit 1; }
[[ -f "$BASE/grafana/provisioning/datasources/prometheus.yaml" ]] || {
  echo "ERROR: datasource de Grafana no disponible"; exit 1;
}
chmod 600 "$PEM"

CFG=$(mktemp)
chmod 600 "$CFG"
trap 'rm -f "$CFG"' EXIT
exec > >(tee "$REPORT") 2>&1
trap 'echo "DESPLIEGUE_INCOMPLETO=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - DESPLIEGUE MONITORING"
echo "=========================================="
date

echo
echo "=== 1. VALIDAR AWS Y CONFIGURAR SSH ==="
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
echo "=== 2. PREPARAR DIRECTORIOS Y SECRETO DE GRAFANA ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_INIT'
set -Eeuo pipefail
TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
INSTANCE=$(curl -fsS -m 5 \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$INSTANCE" == "i-0e3af62685c90f028" ]] || {
  echo "ERROR: instancia EC2 incorrecta"; exit 1;
}
command -v docker >/dev/null
sudo -n docker info >/dev/null
echo "IDENTIDAD_MONITORING=OK"

BASE="/home/ubuntu/dsy1107-ep5/monitoring"
install -d -m 0755 "$BASE"
install -d -m 0755 "$BASE/prometheus"
install -d -m 0755 "$BASE/grafana/provisioning/datasources"
install -d -m 0700 "$BASE/secrets"

SECRET="$BASE/secrets/grafana_password.txt"
if [[ ! -e "$SECRET" ]]; then
  umask 077
  openssl rand -hex 32 > "$SECRET"
  echo "GRAFANA_SECRET=GENERADO"
elif [[ -s "$SECRET" ]]; then
  echo "GRAFANA_SECRET=REUTILIZADO"
else
  echo "ERROR: archivo secreto vacio"; exit 1
fi
# La carpeta 0700 limita el acceso local; Grafana no-root
# requiere permisos de lectura sobre el bind mount del secreto.
chmod 0644 "$SECRET"
echo "GRAFANA_SECRET_CONTENIDO=OCULTO"

# Rechazar colisiones con otros servicios.
for port in 3000 9090; do
  if ss -ltn | grep -Eq ":$port[[:space:]]"; then
    if ! sudo -n docker ps --format '{{.Names}}' |
      grep -Eq '^dsy1107-(grafana|prometheus)$'; then
      echo "ERROR: puerto ocupado por servicio ajeno: $port"
      exit 1
    fi
  fi
done
echo "PREPARACION_DIRECTORIOS=OK"
REMOTE_INIT

echo
echo "=== 3. COPIAR CONFIGURACION VERSIONADA A MONITORING ==="
scp -q -F "$CFG" "$BASE/compose.yaml" \
  "monitoring:$REMOTE_BASE/compose.yaml" </dev/null
scp -q -F "$CFG" "$BASE/prometheus/prometheus.yml" \
  "monitoring:$REMOTE_BASE/prometheus/prometheus.yml" </dev/null
scp -q -F "$CFG" "$BASE/grafana/provisioning/datasources/prometheus.yaml" \
  "monitoring:$REMOTE_BASE/grafana/provisioning/datasources/prometheus.yaml" </dev/null
echo "CONFIGURACIONES_TRANSFERIDAS=OK"

echo
echo "=== 4. VALIDAR COMPOSE Y DESPLEGAR ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_DEPLOY'
set -Eeuo pipefail
cd /home/ubuntu/dsy1107-ep5/monitoring

sudo -n docker compose -f compose.yaml config --quiet
echo "DOCKER_COMPOSE_CONFIG=OK"

sudo -n docker compose -f compose.yaml pull
echo "IMAGENES_DESCARGADAS=OK"

sudo -n docker compose -f compose.yaml up -d
echo "CONTENEDORES_DESPLEGADOS=OK"

echo
echo "--- Contenedores ---"
sudo -n docker compose -f compose.yaml ps

echo
echo "--- Esperar disponibilidad de Prometheus y Grafana ---"
READY=0
for attempt in $(seq 1 40); do
  P=$(curl -sS -m 4 -o /dev/null -w '%{http_code}' \
    http://127.0.0.1:9090/-/ready 2>/dev/null || true)
  G=$(curl -sS -m 4 -o /dev/null -w '%{http_code}' \
    http://127.0.0.1:3000/api/health 2>/dev/null || true)
  if [[ "$P" == "200" && "$G" == "200" ]]; then
    READY=1
    break
  fi
  sleep 3
done
if [[ "$READY" != "1" ]]; then
  echo "ERROR: servicios HTTP no disponibles"
  sudo -n docker compose -f compose.yaml ps
  sudo -n docker compose -f compose.yaml logs --tail 25 prometheus grafana
  exit 1
fi
echo "PROMETHEUS_HTTP=200"
echo "GRAFANA_HTTP=200"

echo
echo "=== 5. VALIDAR METRICAS REALES DE KAFKA ==="
CHECK=$(mktemp)
trap 'rm -f "$CHECK"' EXIT
OK=0
for attempt in $(seq 1 35); do
  curl -fsS -m 8 -G \
    --data-urlencode 'query=kafka_brokers' \
    http://127.0.0.1:9090/api/v1/query \
    > "$CHECK" || true

  if python3 - "$CHECK" <<'PY_METRICS'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    payload=json.load(handle)
values=[float(item["value"][1])
        for item in payload.get("data",{}).get("result",[])]
assert payload.get("status")=="success" and values
assert max(values)>=2, "Se esperaban dos brokers"
print("KAFKA_BROKERS_OBSERVADOS="+str(int(max(values))))
PY_METRICS
  then
    OK=1
    break
  fi
  if (( attempt % 5 == 0 )); then
    echo "ESPERANDO_METRICAS_INTENTO=$attempt/35"
  fi
  sleep 3
done
if [[ "$OK" != "1" ]]; then
  echo "ERROR: Prometheus no recopila dos brokers Kafka"
  sudo -n docker compose -f compose.yaml logs --tail 40 kafka-exporter prometheus
  exit 1
fi
echo "METRICA_KAFKA_BROKERS=OK"

echo
echo "=== 6. SEGURIDAD Y REINICIO AUTOMATICO ==="
for name in dsy1107-prometheus dsy1107-grafana dsy1107-kafka-exporter; do
  sudo -n docker inspect --format \
    'CONTENEDOR={{.Name}} ESTADO={{.State.Status}} RESTART_POLICY={{.HostConfig.RestartPolicy.Name}}' \
    "$name"
  running=$(sudo -n docker inspect -f '{{.State.Running}}' "$name")
  policy=$(sudo -n docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name")
  [[ "$running" == "true" && "$policy" == "unless-stopped" ]] || {
    echo "ERROR: contenedor no persistente: $name"; exit 1;
  }
done

sudo -n docker inspect --format '{{json .HostConfig.PortBindings}}' \
  dsy1107-prometheus dsy1107-grafana dsy1107-kafka-exporter |
python3 -c 'import json,sys
data=[json.loads(x) for x in sys.stdin if x.strip()]
assert len(data)==3, "Contenedores incompletos"
for bindings in data:
    for entries in bindings.values():
        assert all(e.get("HostIp")=="127.0.0.1" for e in entries), \
            "Un servicio tiene puerto publicado fuera de localhost"
assert not data[2], "Kafka Exporter no debe publicar puertos"
print("PUERTOS_PUBLICADOS_SOLO_LOCALHOST=OK")'

echo
echo "=== 7. RECURSOS ==="
free -h
df -h /
echo "MONITORING_SERVICIOS=OK"
REMOTE_DEPLOY

echo
echo "=========================================="
echo " MONITORING DESPLEGADO Y VALIDADO"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
