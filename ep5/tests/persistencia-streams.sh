#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_STREAMS_PERSISTENCIA_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

[[ -f "$PEM" ]] || { echo "ERROR: PEM no encontrada"; exit 1; }
command -v aws >/dev/null
command -v python3 >/dev/null
chmod 600 "$PEM"

APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != "None" ]] || {
  echo "ERROR: APP sin IP publica"; exit 1;
}

CFG=$(mktemp)
TMP=$(mktemp -d)
chmod 600 "$CFG"
RESTARTED=0
cleanup() {
  code=$?
  trap - EXIT
  set +e
  if (( code != 0 )); then
    echo "PRUEBA_INCOMPLETA=SI"
    if (( RESTARTED == 1 )); then
      echo "=== RECUPERACION PREVENTIVA STREAMS ==="
      ssh -n -F "$CFG" app \
        'sudo -n systemctl start dsy1107-ventas-streams.service' || true
      ssh -n -F "$CFG" app \
        'systemctl is-active dsy1107-ventas-streams.service' || true
    fi
    echo "INFORME=$REPORT"
  fi
  rm -f "$CFG"
  rm -rf "$TMP"
  exit "$code"
}
trap cleanup EXIT

cat > "$CFG" <<EOF_SSH
Host app
 HostName $APP_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ConnectTimeout 15
Host kafka2
 HostName 172.31.27.158
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
EOF_SSH

app() { ssh -n -F "$CFG" app "$@"; }
k2() { ssh -n -F "$CFG" kafka2 "$@"; }

produce() {
  local key="$1" payload="$2"
  printf '%s|%s\n' "$key" "$payload" | \
    ssh -T -F "$CFG" kafka2 \
      'sudo -n docker exec -i dsy1107-broker-2 kafka-console-producer --bootstrap-server localhost:9092 --topic ventas-raw --property parse.key=true --property "key.separator=|" --producer-property acks=all'
}

read_aggregates() {
  # Asignacion explicita: no crear un consumer group efimero en cada lectura.
  # --offset earliest permite leer desde el comienzo de cada particion.
  : > "$TMP/aggregated.jsonl"
  : > "$TMP/consumer.log"
  for partition in 0 1; do
    k2 "sudo -n docker exec dsy1107-broker-2 kafka-console-consumer --bootstrap-server localhost:9092 --topic ventas-agregadas --partition $partition --offset earliest --consumer-property isolation.level=read_committed --timeout-ms 6500" \
      >> "$TMP/aggregated.jsonl" 2>> "$TMP/consumer.log" || true
  done
}

check_aggregates() {
  python3 - "$TMP/aggregated.jsonl" "$STORE" "$1" "$2" <<'PY_CHECK'
import json
import sys
from decimal import Decimal

path, store, expected_count, expected_total = sys.argv[1:]
selected = []
with open(path, encoding="utf-8") as source:
    for line in source:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(entry, dict) and entry.get("store") == store:
            selected.append(entry)

expected_count = int(expected_count)
expected_total = Decimal(expected_total)
assert len(selected) == expected_count, (
    f"Cantidad de actualizaciones: {len(selected)} != {expected_count}"
)
assert selected[-1].get("saleCount") == expected_count, (
    "Contador agregado incorrecto"
)
assert Decimal(str(selected[-1].get("totalAmount"))) == expected_total, (
    "Total agregado incorrecto"
)
print("ACTUALIZACIONES_AGREGADAS=" + str(len(selected)))
print("ULTIMA_AGREGACION=" + json.dumps(selected[-1], ensure_ascii=False))
PY_CHECK
}

wait_for() {
  local count="$1" total="$2"
  # Lectura directa de las dos particiones; no provoca rebalanceos de grupos.
  for attempt in $(seq 1 12); do
    read_aggregates
    if check_aggregates "$count" "$total" > "$TMP/check.log" 2>&1; then
      echo "AGREGACION_CONFIRMADA_INTENTO=$attempt"
      cat "$TMP/check.log"
      return 0
    fi
    if (( attempt % 5 == 0 )); then
      echo "ESPERANDO_AGREGACION_INTENTO=$attempt/12"
      echo "SALIDAS_VISIBLES=$(wc -l < "$TMP/aggregated.jsonl")"
    fi
    sleep 2
  done
  echo "ERROR: agregacion no alcanzo los valores esperados tras ampliar la espera"
  cat "$TMP/check.log"
  echo "ULTIMAS_SALIDAS:"
  tail -10 "$TMP/aggregated.jsonl" || true
  echo "CONSUMER_STDERR:"
  tail -5 "$TMP/consumer.log" || true
  echo "ESTADO_STREAMS:"
  app 'systemctl is-active dsy1107-ventas-streams.service' || true
  echo "GRUPO_CONSUMIDOR:"
  k2 'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams --state' || true
  return 1
}

exec > >(tee "$REPORT") 2>&1
echo "=========================================="
echo " DSY1107 - PERSISTENCIA DE KAFKA STREAMS"
echo "=========================================="
date

echo
echo "=== 1. VALIDAR CONDICIONES INICIALES ==="
[[ "$(app 'systemctl is-active dsy1107-ventas-streams.service')" == "active" ]]
[[ "$(k2 'sudo -n docker inspect -f "{{.State.Running}}" dsy1107-broker-2')" == "true" ]]
DESCRIBE=$(k2 'sudo -n docker exec dsy1107-broker-2 kafka-topics --bootstrap-server localhost:9092 --describe --topic ventas-raw')
ISR=$(printf '%s\n' "$DESCRIBE" | awk '/Partition:/ && /Isr: (1,2|2,1)([[:space:]]|$)/ {n++} END {print n+0}')
[[ "$ISR" == "4" ]] || { echo "ERROR: ISR inicial incompleto"; exit 1; }
echo "STREAMS_INICIAL=ACTIVE"
echo "ISR_RAW=4/4"

echo
echo "=== VERIFICAR LECTOR CON UNA VENTA YA CERTIFICADA ==="
read_aggregates
python3 - "$TMP/aggregated.jsonl" <<'PY_PREFLIGHT'
import json
import sys

known = "TIENDA-AUD-20261121202547"
found = False
with open(sys.argv[1], encoding="utf-8") as source:
    for line in source:
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(item, dict) and item.get("store") == known:
            found = True
            break
assert found, "El lector no ve la venta de auditoria anterior: cancelar antes de publicar"
print("LECTOR_PARTICIONES=OK")
print("LECTURA_REFERENCIA_CERTIFICADA=OK")
PY_PREFLIGHT

echo
echo "=== 2. VENTA ORIGINAL ==="
ID1=$(cat /proc/sys/kernel/random/uuid)
ID2=$(cat /proc/sys/kernel/random/uuid)
STORE="PERSIST-$(date -u +%Y%m%d%H%M%S)-$RANDOM"
WHEN=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FIRST=$(printf '{"eventId":"%s","eventTime":"%s","customerId":"cli-pre","store":"%s","price":1200,"quantity":1}' "$ID1" "$WHEN" "$STORE")
SECOND=$(printf '{"eventId":"%s","eventTime":"%s","customerId":"cli-post","store":"%s","price":300,"quantity":1}' "$ID2" "$WHEN" "$STORE")
echo "TIENDA=$STORE"
echo "ID_ORIGINAL=$ID1"
echo "ID_NUEVO=$ID2"
echo "EVENT_TIME=$WHEN"
produce "cliente-original" "$FIRST"
echo "VENTA_ORIGINAL_PUBLICADA=OK"
wait_for 1 1200
echo "AGREGACION_ANTES_REINICIO=OK"

echo
echo "=== 3. REINICIAR EXCLUSIVAMENTE STREAMS ==="
STAMP=$(app "date -u '+%Y-%m-%d %H:%M:%S'")
RESTARTED=1
app 'sudo -n systemctl restart dsy1107-ventas-streams.service'
echo "SYSTEMD_RESTART=OK"
READY=0
for i in $(seq 1 35); do
  STATUS=$(app 'systemctl is-active dsy1107-ventas-streams.service' || true)
  EVENTS=$(app "sudo -n journalctl -u dsy1107-ventas-streams.service --since '$STAMP' --no-pager -o cat | grep -F 'STREAMS_STATE=' | tail -8" || true)
  if [[ "$STATUS" == "active" && "$EVENTS" == *"REBALANCING->RUNNING"* ]]; then
    READY=1
    break
  fi
  sleep 3
done
if [[ "$READY" != "1" ]]; then
  echo "ERROR: Streams no regreso a RUNNING"
  app 'sudo -n journalctl -u dsy1107-ventas-streams.service -n 35 --no-pager -o cat' || true
  exit 1
fi
echo "$EVENTS"
echo "STREAMS_TRAS_REINICIO=RUNNING"

echo
echo "=== 4. DUPLICADO CON OTRA CLAVE + VENTA NUEVA ==="
produce "otra-clave-distinta" "$FIRST"
echo "DUPLICADO_PUBLICADO=OK"
produce "cliente-nuevo" "$SECOND"
echo "VENTA_NUEVA_PUBLICADA=OK"
wait_for 2 1500
sleep 5
read_aggregates
check_aggregates 2 1500
echo "PERSISTENCIA_DEDUP=OK"
echo "AGREGACION_POST_REINICIO=OK"

echo
echo "=== 5. CONFIRMAR REGISTRO DEL DUPLICADO ==="
DUP=$(app "sudo -n journalctl -u dsy1107-ventas-streams.service --since '$STAMP' --no-pager -o cat | grep -F 'DUPLICATE_EVENT_ID=$ID1' | tail -1" || true)
[[ -n "$DUP" ]] || { echo "ERROR: no se hallo evidencia del duplicado"; exit 1; }
echo "$DUP"
echo "DETECCION_DUPLICADO_POST_REINICIO=OK"

echo
echo "=== 6. COMPROBAR GRUPO CONSUMIDOR ==="
k2 'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams --state'
echo "STREAMS_SYSTEMD=$(app 'systemctl is-active dsy1107-ventas-streams.service')"

echo
echo "=========================================="
echo " PRUEBA DE PERSISTENCIA SUPERADA"
echo "=========================================="
echo "STREAMS_PERSISTENCIA=OK"
echo "STREAMS_DEDUP_POST_REINICIO=OK"
echo "INFORME=$REPORT"
