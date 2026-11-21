#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 2 )); then
  echo "Uso: diagnostico-persistencia.sh TIENDA EVENT_ID"
  exit 2
fi
STORE="$1"
EVENT_ID="$2"
PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_PERSISTENCIA_DIAG_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

[[ -f "$PEM" ]] || { echo "ERROR: no existe PEM"; exit 1; }
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
trap 'rm -f "$CFG"; rm -rf "$TMP"' EXIT

cat > "$CFG" <<'EOF_SSH'
Host app
 HostName 184.197.85.64
 User ubuntu
 IdentityFile ~/Downloads/Pedidos360-Key.pem
 IdentitiesOnly yes
 BatchMode yes
 ConnectTimeout 15
Host kafka2
 HostName 172.31.27.158
 User ubuntu
 IdentityFile ~/Downloads/Pedidos360-Key.pem
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
EOF_SSH

# Reemplazar IP publica dinamica de APP y clave, sin exponerlas a los informes.
sed -i "s/184[.]197[.]85[.]64/$APP_IP/g" "$CFG"
sed -i "s|~/Downloads/Pedidos360-Key.pem|$PEM|g" "$CFG"

app() { ssh -n -F "$CFG" app "$@"; }
k2() { ssh -n -F "$CFG" kafka2 "$@"; }

read_topic() {
  local topic="$1"
  k2 "sudo -n docker exec dsy1107-broker-2 kafka-console-consumer --bootstrap-server localhost:9092 --topic $topic --from-beginning --consumer-property isolation.level=read_committed --timeout-ms 10000" \
    > "$TMP/$topic.jsonl" 2> "$TMP/$topic.stderr" || true
}

{
  echo "=========================================="
  echo " DSY1107 - DIAGNOSTICO POST FALLA TEST"
  echo "=========================================="
  date
  echo "TIENDA_INVESTIGADA=$STORE"
  echo "EVENT_ID_INVESTIGADO=$EVENT_ID"

  echo
  echo "=== 1. ESTADO Y TRANSICIONES EN APP ==="
  app 'systemctl show dsy1107-ventas-streams.service -p ActiveState -p SubState -p MainPID -p NRestarts -p ExecMainStatus -p ActiveEnterTimestamp'
  app "sudo -n journalctl -u dsy1107-ventas-streams.service --since '60 minutes ago' --no-pager -o cat | grep -E 'STREAMS_STATE=|STREAMS_INICIADO=|DUPLICATE_EVENT_ID=|ERROR|Exception|WARN|Skipping|expired|late' | tail -65 | cut -c1-330" || true

  echo
  echo "=== 2. ESTADO CONSUMER GROUP EN KAFKA-2 ==="
  k2 'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams --state' || true
  echo
  k2 'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams' || true

  echo
  echo "=== 3. LEER TOPICOS SIN MODIFICAR OFFSETS ==="
  for topic in ventas-raw ventas-agregadas ventas-raw-dlq; do
    read_topic "$topic"
    echo "TOPIC=$topic LINEAS_LEIDAS=$(wc -l < "$TMP/$topic.jsonl")"
    if [[ -s "$TMP/$topic.stderr" ]]; then
      echo "CONSUMER_STDERR_$topic=$(tail -1 "$TMP/$topic.stderr" | cut -c1-200)"
    fi
  done

  echo
  echo "=== 4. BUSCAR MENSAJE Y AGREGACION ==="
  python3 - "$TMP" "$STORE" "$EVENT_ID" <<'PY_DIAG'
import json
import pathlib
import sys

root, store, event_id = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]

def read(topic):
    data = []
    for line in (root / f"{topic}.jsonl").read_text(encoding="utf-8").splitlines():
        try:
            obj = json.loads(line)
            if isinstance(obj, dict):
                data.append(obj)
        except json.JSONDecodeError:
            pass
    return data

raw = [x for x in read("ventas-raw") if x.get("eventId") == event_id]
agg = [x for x in read("ventas-agregadas") if x.get("store") == store]
dlq = [x for x in read("ventas-raw-dlq") if event_id in str(x.get("originalValue", ""))]

print(f"RAW_EVENT_ID_ENCONTRADO={len(raw)}")
print(f"AGREGACIONES_DE_LA_TIENDA={len(agg)}")
print(f"DLQ_CON_EVENT_ID={len(dlq)}")
for label, items in (("RAW", raw), ("AGG", agg), ("DLQ", dlq)):
    for item in items[-3:]:
        print(f"{label}_JSON=" + json.dumps(item, ensure_ascii=False))

if raw and not agg:
    print("HALLAZGO=RAW_PRESENTE_SIN_AGREGACION")
elif not raw:
    print("HALLAZGO=EVENTO_NO_VISIBLE_EN_LECTURA_RAW")
elif agg:
    print("HALLAZGO=AGREGACION_PRESENTE")
PY_DIAG

  echo
  echo "=== 5. ESTADO CONTENEDOR BROKER 2 ==="
  k2 'sudo -n docker inspect --format "BROKER2_RUNNING={{.State.Running}}" dsy1107-broker-2'

  echo
  echo "=========================================="
  echo " DIAGNOSTICO TERMINADO - SOLO LECTURA"
  echo "=========================================="
  echo "INFORME=$REPORT"
} 2>&1 | tee "$REPORT"
