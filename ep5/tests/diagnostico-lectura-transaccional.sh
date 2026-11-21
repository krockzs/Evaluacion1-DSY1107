#!/usr/bin/env bash
set -Eeuo pipefail

STORE="PERSIST-20261121204653-1940"
EVENT_ID="2c611b27-5003-4a0e-9660-3a29477b6fef"
PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_DIAG_TRANSACCIONAL_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

[[ -s "$PEM" ]] || { echo "ERROR: clave PEM no disponible"; exit 1; }
command -v aws >/dev/null
command -v python3 >/dev/null
chmod 600 "$PEM"

APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != "None" ]] || {
  echo "ERROR: APP no tiene IP publica"; exit 1;
}

CFG=$(mktemp)
WORK=$(mktemp -d)
chmod 600 "$CFG"
trap 'rm -f "$CFG"; rm -rf "$WORK"' EXIT

cat > "$CFG" <<EOF_SSH
Host app
 HostName $APP_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ConnectTimeout 15
Host kafka1
 HostName 172.31.91.91
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
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

remote() {
  local host="$1"
  shift
  ssh -n -F "$CFG" "$host" "$@"
}

read_messages() {
  local host="$1" topic="$2" level="$3"
  local file="$WORK/$host-$topic-$level.jsonl"
  local errors="$WORK/$host-$topic-$level.err"
  local container="dsy1107-broker-1"
  [[ "$host" == "kafka2" ]] && container="dsy1107-broker-2"

  remote "$host" \
    "sudo -n docker exec $container kafka-console-consumer --bootstrap-server localhost:9092 --topic $topic --from-beginning --consumer-property isolation.level=$level --timeout-ms 6000" \
    > "$file" 2> "$errors" || true
  echo "LECTURA=$host/$topic/$level MENSAJES=$(wc -l < "$file")"
  if [[ -s "$errors" ]]; then
    echo "STDERR_ULTIMO=$(tail -3 "$errors" | tr '\n' ' ' | cut -c1-350)"
  fi
}

{
  echo "=========================================="
  echo " DSY1107 - DIAGNOSTICO DE LECTURA Y TX"
  echo "=========================================="
  date
  echo "TIENDA=$STORE"
  echo "EVENT_ID=$EVENT_ID"

  echo
  echo "=== 1. VERIFICAR EC2 Y PROCESOS ==="
  for item in "app:i-09732ce35a9b0e22b" "kafka1:i-007b3c21d4d0decea" "kafka2:i-00ac1f46c3ddd6c04"; do
    host=$(printf '%s' "$item" | cut -d: -f1)
    expected=$(printf '%s' "$item" | cut -d: -f2)
    id=$(remote "$host" 'T=$(curl -fsS -m 5 -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token); curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/instance-id')
    [[ "$id" == "$expected" ]] || { echo "ERROR: identidad $host"; exit 1; }
    echo "EC2_$host=OK"
  done

  echo
  echo "=== 2. STREAMS Y ERRORES RECIENTES ==="
  remote app 'systemctl show dsy1107-ventas-streams.service -p ActiveState -p SubState -p MainPID -p NRestarts -p ActiveEnterTimestamp'
  remote app "sudo -n journalctl -u dsy1107-ventas-streams.service --since '45 minutes ago' --no-pager -o cat | grep -Ei 'STREAMS_STATE=|DUPLICATE_EVENT_ID=|exception|error|abort|transaction|skip|expired|late|commit failed|fenced' | tail -65 | cut -c1-300" || true

  echo
  echo "=== 3. SALUD DE AMBOS BROKERS ==="
  for host in kafka1 kafka2; do
    broker=dsy1107-broker-1
    [[ "$host" == kafka2 ]] && broker=dsy1107-broker-2
    echo "--- $host ---"
    remote "$host" "sudo -n docker inspect -f 'RUNNING={{.State.Running}} RESTARTS={{.RestartCount}}' $broker"
    remote "$host" "sudo -n docker stats --no-stream --format '{{.Name}} RAM={{.MemUsage}} CPU={{.CPUPerc}}' $broker"
    remote "$host" "sudo -n docker logs --since 45m --tail 100 $broker 2>&1 | grep -Ei 'ERROR|exception|timeout|transaction|abort|not enough|out of memory|under.replica' | tail -15 | cut -c1-300" || true
  done

  echo
  echo "=== 4. LIDERAZGO, REPLICAS Y LAG ==="
  for topic in ventas-raw ventas-agregadas ventas-raw-dlq __transaction_state; do
    echo "--- $topic ---"
    if [[ "$topic" == "__transaction_state" ]]; then
      remote kafka1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic | head -5" || true
    else
      remote kafka1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic" || true
    fi
  done
  remote kafka2 'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams --state' || true
  remote kafka2 'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams | grep -E "GROUP|ventas-raw|ventas-by-eventid|ventas-ventanas-store" | cut -c1-200' || true

  echo
  echo "=== 5. COMPARAR NIVELES DE AISLAMIENTO ==="
  read_messages kafka2 ventas-raw read_uncommitted
  read_messages kafka2 ventas-raw read_committed
  read_messages kafka2 ventas-agregadas read_uncommitted
  read_messages kafka2 ventas-agregadas read_committed
  read_messages kafka1 ventas-agregadas read_uncommitted
  read_messages kafka1 ventas-agregadas read_committed
  read_messages kafka2 ventas-raw-dlq read_committed

  echo
  echo "=== 6. COMPARAR EL EVENTO EXACTO ==="
  python3 - "$WORK" "$STORE" "$EVENT_ID" <<'PY_COMPARE'
import json
import pathlib
import sys

root, store, event_id = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for file in sorted(root.glob("*.jsonl")):
    matches = []
    for line in file.read_text(encoding="utf-8").splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(rec, dict):
            continue
        if rec.get("eventId") == event_id or rec.get("store") == store \
           or event_id in str(rec.get("originalValue", "")):
            matches.append(rec)
    print("RESULTADO=" + file.stem + " COINCIDENCIAS=" + str(len(matches)))
    for item in matches[-2:]:
        print("REGISTRO=" + json.dumps(item, ensure_ascii=False))

print("DIAGNOSTICO_DATOS=COMPLETADO")
PY_COMPARE

  echo
  echo "=========================================="
  echo " DIAGNOSTICO COMPLETADO (SIN MUTACIONES)"
  echo "=========================================="
  echo "INFORME=$REPORT"
} 2>&1 | tee "$REPORT"
