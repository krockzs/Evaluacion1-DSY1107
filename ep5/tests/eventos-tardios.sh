#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$HOME/PROYECTOS/DUOC/Evaluacion1-DSY1107"
PEM="$HOME/Downloads/Pedidos360-Key.pem"
TEST="ep5/app/streams/src/test/java/cl/duoc/dsy1107/streams/VentasStreamsTest.java"
REPORT="/tmp/DSY1107_EVENTOS_TARDIOS_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

[[ -s "$PEM" ]] || { echo "ERROR: clave PEM ausente"; exit 1; }
cd "$ROOT"
[[ "$(git branch --show-current)" == ep5-app ]] || {
  echo "ERROR: rama Git incorrecta"; exit 1;
}
[[ -z "$(git status --porcelain)" ]] || {
  echo "ERROR: cambios locales Git"; exit 1;
}
chmod 600 "$PEM"

exec > >(tee "$REPORT") 2>&1
trap 'echo "ERROR_EN_LINEA=$LINENO; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - PRUEBAS EVENTOS TARDIOS"
echo "=========================================="
date

echo
echo "=== 1. SINCRONIZAR GITHUB ==="
git pull --ff-only origin ep5-app
grep -Fq 'aceptaTardioDentroDeGraciaYDescartaFueraDeGracia' "$TEST" || {
  echo "ERROR: test de ventanas no encontrado"; exit 1;
}
echo "COMMIT=$(git rev-parse --short HEAD)"
echo "PRUEBA_VERSIONADA=OK"

echo
echo "=== 2. IDENTIDAD AWS ==="
APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != None ]] || {
  echo "ERROR: IP de APP ausente"; exit 1;
}

IDENTITY=$(ssh -n -i "$PEM" -o IdentitiesOnly=yes -o BatchMode=yes \
  -o ConnectTimeout=15 "ubuntu@$APP_IP" \
  'T=$(curl -fsS -m 5 -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token); curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/instance-id')
[[ "$IDENTITY" == i-09732ce35a9b0e22b ]] || {
  echo "ERROR: identidad EC2 distinta"; exit 1;
}
echo "APP_VERIFICADA=OK"

echo
echo "=== 3. ACTUALIZAR SOLO TESTS EN APP ==="
scp -q -i "$PEM" -o IdentitiesOnly=yes -o BatchMode=yes \
  "$TEST" \
  "ubuntu@$APP_IP:/home/ubuntu/dsy1107-ep5/streams/src/test/java/cl/duoc/dsy1107/streams/VentasStreamsTest.java" \
  </dev/null
echo "TEST_JAVA_TRANSFERIDO=OK"

echo
echo "=== 4. EJECUTAR TESTS SIN REINICIAR STREAMS ==="
ssh -T -i "$PEM" -o IdentitiesOnly=yes -o BatchMode=yes \
  "ubuntu@$APP_IP" 'bash -s' <<'REMOTE_TEST'
set -Eeuo pipefail
cd /home/ubuntu/dsy1107-ep5/streams
export MAVEN_OPTS="-Xmx512m"
mvn --batch-mode --no-transfer-progress -Dtest=VentasStreamsTest test
test "$(systemctl is-active dsy1107-ventas-streams.service)" = active
echo "STREAMS_SYSTEMD=active"
echo "TESTS_UNITARIOS_EVENTOS_TARDIOS=OK"
REMOTE_TEST

echo
echo "=========================================="
echo " RESULTADO=OK"
echo "=========================================="
echo "INFORME=$REPORT"
