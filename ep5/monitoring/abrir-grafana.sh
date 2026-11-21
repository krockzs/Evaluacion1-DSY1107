#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_GRAFANA_ACCESO_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

command -v aws >/dev/null
command -v ssh >/dev/null
command -v ss >/dev/null
[[ -s "$PEM" ]] || { echo "ERROR: PEM no encontrado"; exit 1; }
chmod 600 "$PEM"

CFG=$(mktemp)
chmod 600 "$CFG"
trap 'rm -f "$CFG"' EXIT

log() {
  printf '%s\n' "$*" | tee -a "$REPORT"
}

log "=========================================="
log " DSY1107 - ACCESO PRIVADO A GRAFANA"
log "=========================================="
log "$(date)"
log ""
log "=== 1. VALIDAR PUERTO LOCAL ==="

if ss -H -ltn | awk '{print $4}' | grep -Eq ':3000$'; then
  log "ERROR: el puerto 3000 ya esta ocupado en Ryzen"
  log "No se modifico ningun servicio. Libera el puerto local y repite."
  exit 1
fi
log "PUERTO_LOCAL_3000=LIBRE"

log ""
log "=== 2. OBTENER DIRECCIONES AWS ==="
APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
MON_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-0e3af62685c90f028 \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != "None" ]] || {
  log "ERROR: APP no tiene IP publica"; exit 1;
}
[[ "$MON_IP" == "172.31.69.49" ]] || {
  log "ERROR: IP privada de Monitoring inesperada"; exit 1;
}
log "MONITORING_PRIVADA=172.31.69.49"

cat > "$CFG" <<EOF_SSH
Host app
 HostName $APP_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ConnectTimeout 15
 ServerAliveInterval 30
 ServerAliveCountMax 3
Host monitoring
 HostName $MON_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
 ServerAliveInterval 30
 ServerAliveCountMax 3
EOF_SSH

log ""
log "=== 3. VERIFICAR DESTINO Y PANEL ==="
ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_HEALTH' | tee -a "$REPORT"
set -Eeuo pipefail
TOKEN=$(curl -fsS -m 5 -X PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
  http://169.254.169.254/latest/api/token)
ACTUAL=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
[[ "$ACTUAL" == "i-0e3af62685c90f028" ]] || {
  echo "ERROR: identidad AWS incorrecta"; exit 1;
}
curl -fsS --max-time 6 http://127.0.0.1:3000/api/health |
python3 -c 'import json,sys; p=json.load(sys.stdin); assert p.get("database")=="ok", "Grafana sin DB"; print("GRAFANA_SALUD=OK")'
test -s /home/ubuntu/dsy1107-ep5/monitoring/secrets/grafana_password.txt
echo "GRAFANA_CLAVE_DISPONIBLE=SI (no se muestra en el informe)"
REMOTE_HEALTH

log ""
log "=== 4. CREDENCIALES LOCALES (NO SE GUARDAN EN INFORME) ==="
log "USUARIO_GRAFANA=admin"
PASSWORD=$(ssh -n -F "$CFG" monitoring \
  'cat /home/ubuntu/dsy1107-ep5/monitoring/secrets/grafana_password.txt')
[[ "$PASSWORD" =~ ^[[:xdigit:]]{64}$ ]] || {
  log "ERROR: formato inesperado de clave Grafana"; exit 1;
}
if [[ -n "$(printenv DISPLAY 2>/dev/null || true)" ]] && command -v xclip >/dev/null 2>&1; then
  printf '%s' "$PASSWORD" | xclip -selection clipboard
  log "CLAVE_COPIADA_PORTAPAPELES=SI (no compartir la clave)"
elif [[ -n "$(printenv DISPLAY 2>/dev/null || true)" ]] && command -v xsel >/dev/null 2>&1; then
  printf '%s' "$PASSWORD" | xsel --clipboard --input
  log "CLAVE_COPIADA_PORTAPAPELES=SI (no compartir la clave)"
else
  log "CLAVE_COPIADA_PORTAPAPELES=NO"
  printf '\nCLAVE_ADMIN_GRAFANA (SOLO EN TERMINAL, NO COMPARTIR):\n%s\n\n' "$PASSWORD" >/dev/tty
fi
unset PASSWORD

log ""
log "=== 5. ABRIR TUNEL SSH ==="
log "URL_LOCAL=http://127.0.0.1:3000/d/dsy1107-kafka-ep5"
log "TUNEL_LOCAL=127.0.0.1:3000"
log "TUNEL_REMOTO=monitoring:127.0.0.1:3000"
log "Abre la URL en Firefox y usa el usuario admin."
log "Mantiene esta terminal abierta mientras navegas."
log "Para cerrar el tunel, presiona Ctrl+C."
log "INFORME=$REPORT"

ssh -N -F "$CFG" \
  -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:3000:127.0.0.1:3000 \
  monitoring
