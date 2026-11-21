#!/usr/bin/env bash
set -Eeuo pipefail

# DSY1107 EP6: una sola sesion para demostrar y modificar ventas.
# No inicia/detiene EC2 ni reinicia servicios. Solo publica eventos ficticios.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_EP6_DEFENSA_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

TMP=$(mktemp -d)
chmod 700 "$TMP"
CFG="$TMP/ssh_config"
LAST="$TMP/ultimo.json"
PIDS=""
STORE="CLASE-EP6-$(date -u +%Y%m%d%H%M%S)"
MONITORING="172.31.69.49"

cleanup() {
  for pid in $PIDS; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

exec > >(tee "$REPORT") 2>&1

echo "=========================================="
echo " DSY1107 - EP6 | DEFENSA EN VIVO"
echo "=========================================="
echo "INFORME=$REPORT"
echo "Este programa NO reinicia EC2, Kafka ni Streams."
echo "Solo envia eventos de ejemplo cuando confirmes PUBLICAR."
echo

for tool in aws ssh ssh-keygen python3 curl kate; do
  command -v "$tool" >/dev/null || {
    echo "ERROR: falta el comando $tool"; exit 1;
  }
done
[[ -s "$PEM" ]] || { echo "ERROR: falta $PEM"; exit 1; }
chmod 600 "$PEM"

echo "=== Verificar las 4 EC2 de AWS ==="
aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids \
    i-09732ce35a9b0e22b \
    i-007b3c21d4d0decea \
    i-00ac1f46c3ddd6c04 \
    i-0e3af62685c90f028 \
  --output json > "$TMP/aws.json"

APP_IP=$(python3 - "$TMP/aws.json" <<'PY_AWS'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    payload=json.load(f)
instances={x["InstanceId"]:x for res in payload["Reservations"]
           for x in res["Instances"]}
expected={
    "i-09732ce35a9b0e22b":"172.31.25.21",
    "i-007b3c21d4d0decea":"172.31.91.91",
    "i-00ac1f46c3ddd6c04":"172.31.27.158",
    "i-0e3af62685c90f028":"172.31.69.49",
}
assert set(instances)==set(expected), "No estan disponibles las cuatro EC2"
for ident,ip in expected.items():
    obj=instances[ident]
    assert obj["State"]["Name"]=="running", ident+" no esta running"
    assert obj["PrivateIpAddress"]==ip, "IP inesperada: "+ident
    assert obj["VpcId"]=="vpc-0eaa5603256f0610f", "VPC distinta"
app=instances["i-09732ce35a9b0e22b"]
assert app.get("PublicIpAddress"), "APP sin IP publica"
print(app["PublicIpAddress"])
PY_AWS
)
echo "INSTANCIAS=4/4_RUNNING"

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
Host kafka1
 HostName 172.31.91.91
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
 ServerAliveInterval 30
 ServerAliveCountMax 3
Host kafka2
 HostName 172.31.27.158
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
 ServerAliveInterval 30
 ServerAliveCountMax 3
Host monitoring
 HostName $MONITORING
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
 ServerAliveInterval 30
 ServerAliveCountMax 3
EOF_SSH
chmod 600 "$CFG"

# El tunel usa SSH al propio servidor que hospeda cada interfaz.
check_http() {
  local port="$1" path="$2"
  curl -fsS --max-time 5 "http://127.0.0.1:$port$path" >/dev/null 2>&1
}
start_tunnel() {
  local port="$1" remote="$2" target="$3" path="$4"
  if check_http "$port" "$path"; then
    echo "PUERTO_$port=YA_OPERATIVO"
    return 0
  fi
  if ss -H -ltn | awk '{print $4}' | grep -Eq ":$port$"; then
    echo "ERROR: puerto local $port ocupado por otro servicio"; return 1
  fi
  ssh -N -F "$CFG" -o ExitOnForwardFailure=yes \
    -L "127.0.0.1:$port:127.0.0.1:$remote" \
    "$target" > "$TMP/ssh-$port.log" 2>&1 &
  local pid=$!
  PIDS="$PIDS $pid"
  for intento in $(seq 1 20); do
    if check_http "$port" "$path"; then
      echo "TUNEL_$port=OK"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: SSH a $target termino inesperadamente"
      cat "$TMP/ssh-$port.log"
      return 1
    fi
    sleep 1
  done
  echo "ERROR: no responde la interfaz $target:$remote"
  cat "$TMP/ssh-$port.log"
  return 1
}

abrir_interfaces() {
  echo
  echo "=== Abrir Kafka UI y Grafana por tuneles SSH privados ==="
  start_tunnel 18080 8080 kafka1 /
  start_tunnel 3000 3000 monitoring /api/health
  echo "KAFKA_UI=http://127.0.0.1:18080"
  echo "GRAFANA=http://127.0.0.1:3000/d/dsy1107-kafka-ep5"
  echo "GRAFANA_USUARIO=admin"
  echo "La clave no se imprime ni almacena en el informe."
  if command -v xclip >/dev/null 2>&1; then
    ssh -n -F "$CFG" monitoring \
      'cat /home/ubuntu/dsy1107-ep5/monitoring/secrets/grafana_password.txt' |
      xclip -selection clipboard
    echo "GRAFANA_CLAVE=PORTAPAPELES"
  elif command -v xsel >/dev/null 2>&1; then
    ssh -n -F "$CFG" monitoring \
      'cat /home/ubuntu/dsy1107-ep5/monitoring/secrets/grafana_password.txt' |
      xsel --clipboard --input
    echo "GRAFANA_CLAVE=PORTAPAPELES"
  else
    echo "GRAFANA_CLAVE=usar acceso previo o abrir-grafana.sh en otra terminal"
  fi
  firefox 'http://127.0.0.1:18080' >/dev/null 2>&1 &
  firefox 'http://127.0.0.1:3000/d/dsy1107-kafka-ep5' >/dev/null 2>&1 &
  echo "INTERFACES_ABIERTAS=OK"
}

nuevo_json() {
  local destino="$1"
  python3 - "$destino" "$STORE" <<'PY_EVENT'
import datetime
import json
import pathlib
import sys
import uuid
event={
    "eventId":str(uuid.uuid4()),
    "eventTime":datetime.datetime.now(datetime.timezone.utc)
       .isoformat(timespec="seconds").replace("+00:00","Z"),
    "customerId":"cliente-clase-01",
    "store":sys.argv[2],
    "price":1200,
    "quantity":1,
}
pathlib.Path(sys.argv[1]).write_text(
    json.dumps(event,indent=2,ensure_ascii=False)+"\n",
    encoding="utf-8"
)
PY_EVENT
}
preparar_envio() {
  local origen="$1" modo="$2"
  python3 - "$origen" "$TMP/payload.txt" "$modo" "$LAST" <<'PY_PREP'
import json
from pathlib import Path
import sys

src,dst,mode,last=sys.argv[1:]
data=json.loads(Path(src).read_text(encoding="utf-8"))
assert isinstance(data,dict), "El JSON de venta debe ser un objeto"
event_id=data.get("eventId")
assert isinstance(event_id,str) and event_id.strip(), "eventId ausente"
if mode=="duplicado":
    original=json.loads(Path(last).read_text(encoding="utf-8"))
    assert event_id==original.get("eventId"), (
        "Para demostrar duplicado debes conservar el mismo eventId"
    )
    key="cliente-con-clave-distinta"
else:
    key=data.get("customerId") or "cliente-sin-id"
assert isinstance(key,str) and key and "|" not in key and "\n" not in key, \
    "Clave Kafka no valida"
payload=json.dumps(data,ensure_ascii=False,separators=(",",":"))
Path(dst).write_text(key+"|"+payload+"\n",encoding="utf-8")
print("CLAVE_KAFKA="+key)
print("EVENT_ID="+event_id)
print("TIENDA="+str(data.get("store")))
print("EVENT_TIME="+str(data.get("eventTime")))
print("PRECIO="+str(data.get("price")))
print("CANTIDAD="+str(data.get("quantity")))
print("JSON="+payload)
PY_PREP
}

enviar() {
  local origen="$1" modo="$2" confirmacion
  preparar_envio "$origen" "$modo"
  echo
  read -r -p 'Escribe PUBLICAR para enviar a ventas-raw (otro texto cancela): ' confirmacion
  if [[ "$confirmacion" != "PUBLICAR" ]]; then
    echo "ENVIO_CANCELADO=SI"
    return 0
  fi
  # Verificar identidad real de Kafka-2 antes de escribir.
  local actual
  actual=$(ssh -n -F "$CFG" kafka2 \
    'T=$(curl -fsS -m 5 -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token); curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/instance-id')
  [[ "$actual" == "i-00ac1f46c3ddd6c04" ]] || {
    echo "ERROR: SSH no apunta a Kafka-2"; return 1;
  }
  [[ "$(ssh -n -F "$CFG" app 'systemctl is-active dsy1107-ventas-streams.service')" == "active" ]] || {
    echo "ERROR: Streams detenido"; return 1;
  }
  ssh -T -F "$CFG" kafka2 \
    'sudo -n docker exec -i dsy1107-broker-2 kafka-console-producer --bootstrap-server localhost:9092 --topic ventas-raw --property parse.key=true --property "key.separator=|" --producer-property acks=all --producer-property enable.idempotence=true --producer-property delivery.timeout.ms=60000' \
    < "$TMP/payload.txt"
  if [[ "$modo" != "duplicado" ]]; then
    cp "$origen" "$LAST"
  fi
  echo "EVENTO_PUBLICADO=OK"
  echo "Inspecciona ventas-raw, ventas-agregadas y ventas-raw-dlq en Kafka UI."
  echo "Una venta invalida va a DLQ; otra con eventId repetido no se suma."
}

editar_nueva() {
  local archivo="$TMP/venta-editable.json"
  nuevo_json "$archivo"
  echo
  echo "=== VENTA EDITABLE ==="
  echo "Cambia en Kate: price, quantity, eventTime, eventId, customerId o store."
  echo "Prueba invalida: quantity = 0; prueba tardia: modifica eventTime."
  echo "Para sumar a la misma ventana, conserva la tienda y usa un nuevo eventId."
  kate "$archivo" >/dev/null 2>&1 &
  read -r -p 'Guarda el JSON con Ctrl+S y presiona ENTER aqui para revisarlo... ' _
  enviar "$archivo" normal
  if [[ -s "$LAST" ]]; then
    STORE=$(python3 - "$LAST" <<'PY_STORE'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:
    print(json.load(f).get("store") or "CLASE-EP6")
PY_STORE
)
  fi
}

editar_duplicado() {
  if [[ ! -s "$LAST" ]]; then
    echo "Primero publica una venta con la opcion 2."
    return
  fi
  local archivo="$TMP/venta-duplicada.json"
  cp "$LAST" "$archivo"
  echo
  echo "=== DUPLICADO CONTROLADO ==="
  echo "Mantén el MISMO eventId. Puedes alterar price, quantity o customerId."
  echo "El procesador debe descartar el evento aunque cambie su clave Kafka."
  kate "$archivo" >/dev/null 2>&1 &
  read -r -p 'Guarda con Ctrl+S; luego ENTER para revisar duplicado... ' _
  enviar "$archivo" duplicado
}

codigo_y_config() {
  echo
  echo "=== CODIGO Y CONFIGURACION DE LA RUBRICA EP6 ==="
  kate \
    "$ROOT/ep5/app/streams/src/main/java/cl/duoc/dsy1107/streams/VentasStreams.java" \
    "$ROOT/ep5/app/streams/src/test/java/cl/duoc/dsy1107/streams/VentasStreamsTest.java" \
    "$ROOT/ep5/app/producer/src/main/java/cl/duoc/dsy1107/producer/VentasProducer.java" \
    "$ROOT/ep5/monitoring/compose.yaml" \
    "$ROOT/ep5/monitoring/prometheus/prometheus.yml" \
    >/dev/null 2>&1 &
  echo "CODIGO_KATE=ABIERTO"
  echo
  echo "--- Estado de Kafka Streams ---"
  ssh -n -F "$CFG" app \
    'systemctl show dsy1107-ventas-streams.service -p ActiveState -p FragmentPath -p ExecStart -p Restart -p EnvironmentFiles'
  echo
  echo "--- Topicos: particiones, RF e ISR ---"
  for topic in ventas-raw ventas-agregadas ventas-raw-dlq; do
    echo "TOPICO=$topic"
    ssh -n -F "$CFG" kafka2 \
      "sudo -n docker exec dsy1107-broker-2 kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic"
    echo "RETENCION_EXPLICITA_$topic:"
    ssh -n -F "$CFG" kafka2 \
      "sudo -n docker exec dsy1107-broker-2 kafka-configs --bootstrap-server localhost:9092 --entity-type topics --entity-name $topic --describe"
  done
  echo
  echo "--- Configuracion no sensible del broker (retencion por defecto si aplica) ---"
  ssh -n -F "$CFG" kafka2 \
    'sudo -n docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" dsy1107-broker-2 | grep -E "^KAFKA_(BROKER_ID|MIN_INSYNC_REPLICAS|DEFAULT_REPLICATION_FACTOR|LOG_RETENTION_HOURS|LOG_RETENTION_MS|LOG_RETENTION_BYTES|LOG_SEGMENT_BYTES)=" || true'
  echo "Si no aparece retention.ms en el topico, hereda el valor del broker."
  echo
  echo "--- Grupo consumidor: asignacion, offset y lag ---"
  ssh -n -F "$CFG" kafka2 \
    'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams'
  echo
  echo "CONFIGURACION_CONSULTADA=OK"
}

echo
echo "Preparado. Abre las interfaces y modifica ventas en la misma sesion."

while true; do
  echo
  echo "------------------------------------------"
  echo " 1) Abrir Kafka UI y Grafana"
  echo " 2) Crear / EDITAR / publicar una venta"
  echo " 3) Repetir un eventId (deduplicacion)"
  echo " 4) Ver codigo y configuracion REAL"
  echo " 5) Salir"
  echo "------------------------------------------"
  read -r -p 'Elige [1-5]: ' OPCION || break
  case "$OPCION" in
    1) abrir_interfaces ;;
    2) editar_nueva ;;
    3) editar_duplicado ;;
    4) codigo_y_config ;;
    5) break ;;
    *) echo "Opcion no valida" ;;
  esac
done

echo "DEFENSA_FINALIZADA=SI"
echo "INFORME=$REPORT"
