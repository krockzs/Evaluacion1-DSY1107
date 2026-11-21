#!/usr/bin/env bash
set -Eeuo pipefail

PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_KAFKA_FAILOVER_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER=""
export AWS_CLI_AUTO_PROMPT=off

[[ -f "$PEM" ]] || { echo "ERROR: PEM no encontrada"; exit 1; }
chmod 600 "$PEM"
APP_IP=$(aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids i-09732ce35a9b0e22b \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[[ -n "$APP_IP" && "$APP_IP" != "None" ]] || {
  echo "ERROR: APP sin IP publica"; exit 1;
}

SSH_CONFIG=$(mktemp)
chmod 600 "$SSH_CONFIG"
MUST_RESTORE=0

cleanup() {
  result=$?
  trap - EXIT
  set +e
  if [[ "$MUST_RESTORE" == "1" ]]; then
    echo
    echo "=== RECUPERACION AUTOMATICA DEL BROKER 2 ==="
    if ssh -n -F "$SSH_CONFIG" kafka2 \
      'sudo -n docker start dsy1107-broker-2'; then
      echo "REINICIO_SOLICITADO=OK"
      echo "ATENCION: revisar ISR antes de certificar recuperacion"
    else
      echo "ALERTA: fallo restauracion remota"
      echo "En Kafka-2 ejecutar: sudo docker start dsy1107-broker-2"
    fi
  fi
  rm -f "$SSH_CONFIG"
  if (( result != 0 )); then
    echo "PRUEBA_INCOMPLETA=SI"
    echo "INFORME=$REPORT"
  fi
  exit "$result"
}
trap cleanup EXIT

cat > "$SSH_CONFIG" <<EOF_SSH
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
    ProxyJump app
    BatchMode yes
    ConnectTimeout 15

Host kafka2
    HostName 172.31.27.158
    User ubuntu
    IdentityFile $PEM
    IdentitiesOnly yes
    ProxyJump app
    BatchMode yes
    ConnectTimeout 15
EOF_SSH

k1() { ssh -n -F "$SSH_CONFIG" kafka1 "$@"; }
k2() { ssh -n -F "$SSH_CONFIG" kafka2 "$@"; }

exec > >(tee "$REPORT") 2>&1
echo "=========================================="
echo " DSY1107 - PRUEBA FAILOVER BROKER 2"
echo "=========================================="
date

echo
echo "=== 1. VALIDAR INSTANCIAS AWS ==="
for spec in 'kafka1:i-007b3c21d4d0decea' 'kafka2:i-00ac1f46c3ddd6c04'; do
  host=$(printf '%s' "$spec" | cut -d: -f1)
  expected=$(printf '%s' "$spec" | cut -d: -f2)
  actual=$(ssh -n -F "$SSH_CONFIG" "$host" \
    'TOKEN=$(curl -fsS -m 5 -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token) && curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id')
  [[ "$actual" == "$expected" ]] || {
    echo "ERROR: instancia incorrecta: $host"; exit 1;
  }
  echo "IDENTIDAD_$host=OK"
done

[[ "$(k1 'sudo -n docker inspect -f "{{.State.Running}}" dsy1107-broker-1')" == "true" ]]
[[ "$(k2 'sudo -n docker inspect -f "{{.State.Running}}" dsy1107-broker-2')" == "true" ]]
echo "BROKERS_INICIALES=2/2"

initial=$(k1 'sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic ventas-raw')
count=$(printf '%s\n' "$initial" | awk '/Partition:/ && /Isr: (1,2|2,1)([[:space:]]|$)/ {n++} END {print n+0}')
[[ "$count" == "4" ]] || { echo "ERROR: ISR inicial incompleto"; exit 1; }
echo "ISR_VENTAS_RAW_INICIAL=4/4"

echo
echo "=== 2. CREAR TOPICO TEMPORAL ==="
TOPIC="dsy1107-failover-$(date -u +%Y%m%d%H%M%S)-$RANDOM"
k1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --create --topic $TOPIC --partitions 1 --replication-factor 2 --config min.insync.replicas=1"

ready=0
for i in $(seq 1 20); do
  desc=$(k1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic $TOPIC" 2>/dev/null || true)
  if [[ "$desc" == *"Isr: 1,2"* || "$desc" == *"Isr: 2,1"* ]]; then
    ready=1; break
  fi
  sleep 2
done
[[ "$ready" == "1" ]] || { echo "ERROR: topico temporal sin ISR completo"; exit 1; }
echo "TOPICO_TEMPORAL=$TOPIC"
echo "ISR_TEMPORAL_INICIAL=2/2"

echo
echo "=== 3. DETENER KAFKA-2 ==="
MUST_RESTORE=1
k2 'sudo -n docker stop --time 30 dsy1107-broker-2'

ready=0
for i in $(seq 1 30); do
  desc=$(k1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic $TOPIC" 2>/dev/null || true)
  if [[ "$desc" == *"Leader: 1"* && "$desc" == *"Isr: 1"* ]]; then
    ready=1; break
  fi
  sleep 2
done
[[ "$ready" == "1" ]] || { echo "ERROR: no se produjo failover al broker 1"; exit 1; }
echo "BROKER_2_DETENIDO=OK"
echo "LIDER_DURANTE_FALLO=1"
echo "ISR_DURANTE_FALLO=1"

echo
echo "=== 4. PRODUCIR Y CONSUMIR SIN KAFKA-2 ==="
PAYLOAD="mensaje-durante-fallo-$TOPIC"
printf '%s\n' "$PAYLOAD" | ssh -T -F "$SSH_CONFIG" kafka1 \
  "sudo -n docker exec -i dsy1107-broker-1 kafka-console-producer --bootstrap-server localhost:9092 --topic $TOPIC --producer-property acks=all --producer-property request.timeout.ms=15000 --producer-property delivery.timeout.ms=30000"

received=$(k1 "sudo -n docker exec dsy1107-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic $TOPIC --partition 0 --offset earliest --max-messages 1 --timeout-ms 20000 2>/dev/null")
[[ "$received" == "$PAYLOAD" ]] || { echo "ERROR: lectura durante fallo incorrecta"; exit 1; }
echo "ESCRITURA_CON_UN_BROKER=OK"
echo "LECTURA_CON_UN_BROKER=OK"
echo "MENSAJE=$PAYLOAD"

echo
echo "=== 5. RECUPERAR KAFKA-2 ==="
k2 'sudo -n docker start dsy1107-broker-2'
ready=0
for i in $(seq 1 45); do
  desc=$(k1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic $TOPIC" 2>/dev/null || true)
  if [[ "$desc" == *"Isr: 1,2"* || "$desc" == *"Isr: 2,1"* ]]; then
    ready=1; break
  fi
  sleep 3
done
[[ "$ready" == "1" ]] || { echo "ERROR: ISR temporal no recuperado"; exit 1; }
echo "ISR_TEMPORAL_RECUPERADO=2/2"

echo
echo "=== 6. RECUPERACION DE TOPICOS EP5 ==="
for spec in 'ventas-raw:4' 'ventas-agregadas:2' 'ventas-raw-dlq:4'; do
  topic=$(printf '%s' "$spec" | cut -d: -f1)
  expected=$(printf '%s' "$spec" | cut -d: -f2)
  ready=0
  for i in $(seq 1 25); do
    desc=$(k1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic")
    count=$(printf '%s\n' "$desc" | awk '/Partition:/ && /Isr: (1,2|2,1)([[:space:]]|$)/ {n++} END {print n+0}')
    if [[ "$count" == "$expected" ]]; then
      ready=1; break
    fi
    sleep 2
  done
  [[ "$ready" == "1" ]] || { echo "ERROR: ISR incompleto: $topic"; exit 1; }
  echo "ISR_$topic=$count/$expected"
done

echo
echo "=== 7. LEER DESDE EL BROKER RECUPERADO ==="
received=$(k2 "sudo -n docker exec dsy1107-broker-2 kafka-console-consumer --bootstrap-server localhost:9092 --topic $TOPIC --partition 0 --offset earliest --max-messages 1 --timeout-ms 20000 2>/dev/null")
[[ "$received" == "$PAYLOAD" ]] || { echo "ERROR: Kafka-2 no recupero el mensaje"; exit 1; }
echo "LECTURA_POST_RECUPERACION=OK"
MUST_RESTORE=0

echo
echo "=== 8. ELIMINAR TOPICO TEMPORAL ==="
k1 "sudo -n docker exec dsy1107-broker-1 kafka-topics --bootstrap-server localhost:9092 --delete --topic $TOPIC"
echo "BORRADO_TEMPORAL_SOLICITADO=OK"

echo
echo "=== 9. VERIFICAR KAFKA STREAMS ==="
app_state=$(ssh -n -F "$SSH_CONFIG" app 'systemctl is-active dsy1107-ventas-streams.service')
echo "STREAMS_SYSTEMD=$app_state"
[[ "$app_state" == "active" ]] || { echo "ERROR: Kafka Streams no esta activo"; exit 1; }

echo
echo "=========================================="
echo " FAILOVER KAFKA-2 SUPERADO"
echo "=========================================="
echo "FAILOVER_KAFKA_2=OK"
echo "RECUPERACION_ISR=OK"
echo "INFORME=$REPORT"
kate "$REPORT"
