#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_MONITORING_DOCKER_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

[[ -s "$PEM" ]] || { echo "ERROR: falta la clave SSH"; exit 1; }
command -v aws >/dev/null
chmod 600 "$PEM"
CFG=$(mktemp)
chmod 600 "$CFG"
trap 'rm -f "$CFG"' EXIT

exec > >(tee "$REPORT") 2>&1
trap 'echo "INSTALACION_INCOMPLETA=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - PREPARACION DOCKER MONITORING"
echo "=========================================="
date

echo
echo "=== 1. VALIDAR DESTINO AWS ==="
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
echo "=== 2. INSTALAR DOCKER OFICIAL EN MONITORING ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'MON_DOCKER'
set -Eeuo pipefail

TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
EC2_INSTANCE_ID=$(curl -fsS -m 5 \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$EC2_INSTANCE_ID" == "i-0e3af62685c90f028" ]] || {
  echo "ERROR: identidad EC2 Monitoring incorrecta"; exit 1;
}
sudo -n true
. /etc/os-release
[[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]] || {
  echo "ERROR: sistema operativo no esperado"; exit 1;
}
[[ "$(dpkg --print-architecture)" == "amd64" ]] || {
  echo "ERROR: arquitectura diferente de amd64"; exit 1;
}
echo "INSTANCIA_VERIFICADA=$EC2_INSTANCE_ID"
echo "UBUNTU_VERSION=$VERSION_ID"

echo
echo "--- Verificar conflictos con paquetes alternativos ---"
for pkg in docker.io docker-compose docker-compose-v2 podman-docker; do
  if dpkg -s "$pkg" 2>/dev/null | grep -qx 'Status: install ok installed'; then
    echo "ERROR: paquete en conflicto $pkg; no se modificara automaticamente"
    exit 1
  fi
done
echo "PAQUETES_CONFLICTIVOS=NINGUNO"

echo
echo "--- Repositorio e instalacion oficial ---"
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  ARCH=$(dpkg --print-architecture)
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF_DOCKER_SOURCES
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: $ARCH
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER_SOURCES

  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
else
  echo "DOCKER_BINARIO_PREEXISTENTE=SI"
  command -v docker
fi

echo
echo "--- Servicios persistentes ---"
sudo systemctl enable --now containerd.service
sudo systemctl enable --now docker.service
sudo docker info --format 'DOCKER_SERVER_VERSION={{.ServerVersion}}'
sudo docker compose version
echo "DOCKER_SYSTEMD=$(systemctl is-enabled docker.service)"
echo "DOCKER_ACTIVE=$(systemctl is-active docker.service)"
echo "CONTAINERD_ACTIVE=$(systemctl is-active containerd.service)"
echo
echo "--- Recursos despues de la instalacion ---"
free -h
df -h /
echo
echo "MONITORING_DOCKER=OK"
MON_DOCKER

echo
echo "=========================================="
echo " PREPARACION DOCKER COMPLETADA"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
