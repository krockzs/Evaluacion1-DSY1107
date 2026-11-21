#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_MONITORING_INVENTARIO_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

[[ -s "$PEM" ]] || { echo "ERROR: clave PEM no disponible"; exit 1; }
command -v aws >/dev/null
chmod 600 "$PEM"
CFG=$(mktemp)
chmod 600 "$CFG"
trap 'rm -f "$CFG"' EXIT

exec > >(tee "$REPORT") 2>&1
trap 'echo "INVENTARIO_INCOMPLETO=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - INVENTARIO EC2 MONITORING"
echo "=========================================="
date

echo
echo "=== 1. DATOS EC2 AWS ==="
APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
MON_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-0e3af62685c90f028 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != "None" ]] || {
  echo "ERROR: APP sin IP publica"; exit 1;
}
[[ -n "$MON_IP" && "$MON_IP" != "None" ]] || {
  echo "ERROR: Monitoring sin IP privada"; exit 1;
}

aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-0e3af62685c90f028 \
  --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,Type:InstanceType,PrivateIP:PrivateIpAddress,SecurityGroups:SecurityGroups[*].GroupId}' \
  --output json
echo "APP_PUBLICA=$APP_IP"
echo "MONITORING_PRIVADA=$MON_IP"

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
echo "=== 2. INVENTARIO EN MONITORING (SOLO LECTURA) ==="

ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_MON'
set -Eeuo pipefail
TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
ACTUAL=$(curl -fsS -m 5 \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$ACTUAL" == "i-0e3af62685c90f028" ]] || {
  echo "ERROR: identidad EC2 Monitoring incorrecta"; exit 1;
}
echo "IDENTIDAD_MONITORING=OK"
echo "HOSTNAME=$(hostname)"
echo "OS=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2-)"
echo "UPTIME=$(uptime -p)"
echo
echo "--- Recursos ---"
free -h
df -h /
echo
echo "--- Docker y Compose ---"
if command -v docker >/dev/null 2>&1; then
  docker --version
  if sudo -n docker info >/dev/null 2>&1; then
    echo "DOCKER_DAEMON=ACCESSIBLE"
    sudo -n docker ps -a --format 'CONTENEDOR={{.Names}} IMAGEN={{.Image}} ESTADO={{.Status}} PUERTOS={{.Ports}}'
    sudo -n docker compose ls --all 2>/dev/null || true
  else
    echo "DOCKER_DAEMON=NO_ACCESS"
  fi
else
  echo "DOCKER=NO_INSTALADO"
fi
echo
echo "--- Servicios observabilidad ---"
systemctl list-unit-files --type=service --no-pager |
  grep -Ei 'prometheus|grafana|exporter|cadvisor|kafka|jmx' || true
systemctl list-units --type=service --state=running --no-pager |
  grep -Ei 'prometheus|grafana|exporter|cadvisor|kafka|jmx' || true
echo
echo "--- Puertos de escucha comunes ---"
ss -ltn |
  grep -E ':(3000|9090|9100|9308|9404|7071|8080)([[:space:]]|$)' || true
echo
echo "--- Servicios HTTP localhost ---"
for item in '9090:/-/ready' '3000:/api/health' '9100:/metrics'; do
  IFS=: read -r port endpoint <<< "$item"
  code=$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$port$endpoint" 2>/dev/null || true)
  echo "HTTP_LOCAL_$port=$code"
done
echo
echo "--- Configuraciones localizadas (solo rutas, no secretos) ---"
for dir in /etc/prometheus /etc/grafana /opt/monitoring /home/ubuntu; do
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 2 -type f \
      \( -name 'prometheus.yml' -o -name 'docker-compose.yml' \
         -o -name 'compose.yml' -o -name 'grafana.ini' \
         -o -name 'kafka_exporter.service' -o -name 'node_exporter.service' \) \
      -print 2>/dev/null | head -35
  fi
done

echo
echo "--- Conectividad TCP desde Monitoring ---"
for target in '172.31.91.91:9092' '172.31.27.158:9092' \
              '172.31.25.21:9092' '172.31.25.21:9404' \
              '172.31.91.91:7071' '172.31.27.158:7071' \
              '172.31.91.91:9308' '172.31.27.158:9308'; do
  host=$(printf '%s' "$target" | cut -d: -f1)
  port=$(printf '%s' "$target" | cut -d: -f2)
  if timeout 3 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
    echo "TCP_$target=OPEN"
  else
    echo "TCP_$target=CLOSED_OR_FILTERED"
  fi
done

echo
echo "MONITORING_INVENTARIO_REMOTO=OK"
REMOTE_MON

echo
echo "=========================================="
echo " INVENTARIO TERMINADO - SIN MODIFICACIONES"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
