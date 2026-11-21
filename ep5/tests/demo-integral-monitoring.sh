#!/usr/bin/env bash
set -Eeuo pipefail

# DSY1107 EP5: demostracion end-to-end con observabilidad real.
# No reinicia servicios ni modifica configuraciones. Publica ocho eventos ficticios.
PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_DEMO_INTEGRAL_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

command -v aws >/dev/null
command -v python3 >/dev/null
[[ -s "$PEM" ]] || { echo "ERROR: no se encontro PEM"; exit 1; }
chmod 600 "$PEM"
TMP=$(mktemp -d)
CFG="$TMP/ssh_config"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT
exec > >(tee "$REPORT") 2>&1
trap 'echo "DEMO_INCOMPLETA=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - DEMOSTRACION INTEGRAL EP5"
echo "=========================================="
date
echo
echo "OBJETIVO=Kafka Raw -> Streams -> Agregadas/DLQ -> Prometheus/Grafana"
echo "DATOS=100% ficticios; sin reiniciar servicios"

echo
echo "=== 1. IDENTIDAD AWS Y CONECTIVIDAD SSH ==="
aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
  --instance-ids \
    i-09732ce35a9b0e22b \
    i-00ac1f46c3ddd6c04 \
    i-0e3af62685c90f028 \
  --output json > "$TMP/instances.json"

APP_IP=$(python3 - "$TMP/instances.json" <<'PY_INST'
import json
import sys

expected={
    "i-09732ce35a9b0e22b":("172.31.25.21",None),
    "i-00ac1f46c3ddd6c04":("172.31.27.158",None),
    "i-0e3af62685c90f028":("172.31.69.49","sg-04a36e10adc053871"),
}
with open(sys.argv[1],encoding="utf-8") as fh:
    data=json.load(fh)
instances={x["InstanceId"]:x for r in data["Reservations"]
           for x in r["Instances"]}
assert set(instances)==set(expected), "Inventario AWS incompleto"
for ident,(ip,sg) in expected.items():
    item=instances[ident]
    assert item["State"]["Name"]=="running", "EC2 no esta running"
    assert item["PrivateIpAddress"]==ip, "IP privada inesperada"
    assert item["VpcId"]=="vpc-0eaa5603256f0610f", "VPC distinta"
    if sg:
        assert sg in {x["GroupId"] for x in item["SecurityGroups"]}
app=instances["i-09732ce35a9b0e22b"]
assert app.get("PublicIpAddress"), "APP sin IP publica"
print(app["PublicIpAddress"])
PY_INST
)
echo "INSTANCIAS_AWS=VERIFICADAS"

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
Host monitoring
 HostName 172.31.69.49
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
EOF_SSH
chmod 600 "$CFG"

check_remote() {
  local name="$1" expected="$2" actual
  actual=$(ssh -n -F "$CFG" "$name" \
    'TOKEN=$(curl -fsS -m 5 -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" http://169.254.169.254/latest/api/token) && curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id')
  [[ "$actual" == "$expected" ]] || {
    echo "ERROR: SSH $name apunta a otra instancia"; exit 1;
  }
  echo "SSH_IDENTIDAD_$name=OK"
}
check_remote app i-09732ce35a9b0e22b
check_remote kafka2 i-00ac1f46c3ddd6c04
check_remote monitoring i-0e3af62685c90f028

app() { ssh -n -F "$CFG" app "$@"; }
k2() { ssh -n -F "$CFG" kafka2 "$@"; }

echo
echo "=== 2. PREFLIGHT CLUSTER Y STREAMS ==="
[[ "$(app 'systemctl is-active dsy1107-ventas-streams.service')" == "active" ]] || {
  echo "ERROR: Streams no esta activo"; exit 1;
}
[[ "$(k2 'sudo -n docker inspect -f "{{.State.Running}}" dsy1107-broker-2')" == "true" ]] || {
  echo "ERROR: broker-2 no esta activo"; exit 1;
}
for topic in ventas-raw ventas-agregadas ventas-raw-dlq; do
  k2 "sudo -n docker exec dsy1107-broker-2 kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic" \
    > "$TMP/topic-$topic.txt"
done
python3 - "$TMP" <<'PY_TOPICS'
import pathlib
import re
import sys
base=pathlib.Path(sys.argv[1])
for name,expected in (("ventas-raw",4),("ventas-agregadas",2),("ventas-raw-dlq",4)):
    text=(base/("topic-"+name+".txt")).read_text(encoding="utf-8")
    lines=[x for x in text.splitlines() if "Partition:" in x]
    assert len(lines)==expected, "Particiones inesperadas: "+name
    for line in lines:
        m=re.search(r"Isr:\s*([0-9,]+)",line)
        assert m and set(m.group(1).split(","))=={"1","2"}, \
            "ISR no recuperado para "+name
    print("ISR_"+name+"="+str(expected)+"/"+str(expected))
print("BROKERS_Y_REPLICAS=OK")
PY_TOPICS
echo "STREAMS_SYSTEMD=active"

# El mismo programa toma instantaneas de Prometheus antes y despues.
snapshot() {
  ssh -T -F "$CFG" monitoring 'python3 -' <<'PY_SNAPSHOT'
import json
import urllib.parse
import urllib.request

BASE="http://127.0.0.1:9090"
def query(expr):
    address=BASE+"/api/v1/query?"+urllib.parse.urlencode({"query":expr})
    with urllib.request.urlopen(address, timeout=12) as response:
        data=json.load(response)
    assert data["status"]=="success", "API Prometheus no exitosa"
    return [float(x["value"][1]) for x in data["data"]["result"]]

def metric(expr):
    values=query(expr)
    assert values, "Sin series para "+expr
    return sum(values)

result={
    "brokers":max(query("kafka_brokers")),
    "raw":metric('kafka_topic_partition_current_offset{topic="ventas-raw"}'),
    "aggregated":metric('kafka_topic_partition_current_offset{topic="ventas-agregadas"}'),
    "dlq":metric('kafka_topic_partition_current_offset{topic="ventas-raw-dlq"}'),
}
assert result["brokers"]>=2
with urllib.request.urlopen(BASE+"/api/v1/targets",timeout=12) as response:
    targets=json.load(response)
jobs={
    x.get("labels",{}).get("job"):x.get("health")
    for x in targets["data"]["activeTargets"]
}
assert jobs.get("prometheus")=="up" and jobs.get("kafka-exporter")=="up"
print(json.dumps(result,sort_keys=True))
PY_SNAPSHOT
}

echo
echo "=== 3. CAPTURAR METRICAS ANTES DE LA DEMO ==="
snapshot > "$TMP/before.json"
python3 - "$TMP/before.json" <<'PY_BEFORE'
import json
import sys
with open(sys.argv[1],encoding="utf-8") as f: data=json.load(f)
for key in ("brokers","raw","aggregated","dlq"):
    print("METRICA_INICIAL_"+key.upper()+"="+str(data[key]))
print("PROMETHEUS_PREFLIGHT=OK")
PY_BEFORE

echo
echo "=== 4. GENERAR EXACTAMENTE OCHO EVENTOS FICTICIOS ==="
python3 - "$TMP/messages.txt" "$TMP/demo.json" <<'PY_MESSAGES'
from datetime import datetime,timezone
import json
from pathlib import Path
import sys
from uuid import uuid4

out=Path(sys.argv[1])
meta=Path(sys.argv[2])
timestamp=datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z")
store="DEMO-EP5-"+datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")+"-"+uuid4().hex[:8]
prices=[100,200,300,400,500,600]
rows=[]
for idx,price in enumerate(prices,1):
    event={
        "eventId":str(uuid4()),
        "eventTime":timestamp,
        "customerId":"cliente-ficticio-"+str(idx),
        "store":store,
        "price":price,
        "quantity":1,
    }
    rows.append(("demo-cliente-"+str(idx),event))
duplicate_id=rows[0][1]["eventId"]
rows.append(("demo-otra-clave",dict(rows[0][1])))
invalid=dict(rows[0][1])
invalid.update(eventId=str(uuid4()),customerId="cliente-ficticio-invalido",
               price=50,quantity=0)
rows.append(("demo-invalido",invalid))
with out.open("w",encoding="utf-8") as fh:
    for key,event in rows:
        fh.write(key+"|"+json.dumps(event,separators=(",",":"),ensure_ascii=False)+"\n")
assert len(rows)==8
meta.write_text(json.dumps({
    "store":store,
    "duplicateId":duplicate_id,
    "invalidId":invalid["eventId"],
    "time":timestamp,
    "validCount":6,
    "expectedTotal":"2100.0",
    "rawMessages":8,
    "expectedReason":"quantity_entero_positivo_requerido",
},indent=2),encoding="utf-8")
print("TIENDA_DEMO="+store)
print("EVENT_TIME="+timestamp)
print("EVENTOS_VALIDOS=6")
print("DUPLICADOS=1")
print("INVALIDOS_DLQ=1")
print("TOTAL_ESPERADO=2100.0")
print("MENSAJES_RAW_PREPARADOS=8")
PY_MESSAGES

START_EPOCH=$(date +%s)
echo
echo "=== 5. PUBLICAR LOS OCHO EVENTOS EN ventas-raw ==="
ssh -T -F "$CFG" kafka2 \
 'sudo -n docker exec -i dsy1107-broker-2 kafka-console-producer --bootstrap-server localhost:9092 --topic ventas-raw --property parse.key=true --property "key.separator=|" --producer-property acks=all --producer-property enable.idempotence=true --producer-property delivery.timeout.ms=60000' \
 < "$TMP/messages.txt"
echo "RAW_EVENTOS_PUBLICADOS=8"
echo "ACKS=all"
echo "PRODUCTOR_IDEMPOTENTE=SI"

read_topic() {
  local topic="$1" partitions="$2" dest="$3" part
  : > "$dest"
  for ((part=0;part<partitions;part++)); do
    k2 "sudo -n docker exec dsy1107-broker-2 kafka-console-consumer --bootstrap-server localhost:9092 --topic $topic --partition $part --offset earliest --consumer-property isolation.level=read_committed --timeout-ms 4500" \
      >> "$dest" 2>> "$TMP/consumer-stderr.log" || true
  done
}
verify_aggregate() {
  python3 - "$TMP/aggregate.jsonl" "$TMP/demo.json" <<'PY_AGG'
import json
from decimal import Decimal
import sys
with open(sys.argv[2],encoding="utf-8") as fh: meta=json.load(fh)
records=[]
with open(sys.argv[1],encoding="utf-8") as fh:
    for line in fh:
        try: item=json.loads(line)
        except json.JSONDecodeError: continue
        if isinstance(item,dict) and item.get("store")==meta["store"]:
            records.append(item)
assert records, "Sin agregaciones de esta tienda"
last=records[-1]
assert last.get("saleCount")==meta["validCount"], \
    "Conteo final de ventas aun no es el esperado"
assert Decimal(str(last.get("totalAmount")))==Decimal(meta["expectedTotal"]), \
    "Total agregado no coincide"
assert max(x.get("saleCount",0) for x in records)==meta["validCount"], \
    "Existe una agregacion superior: revisar deduplicacion"
print("AGREGACIONES_DEMO="+str(len(records)))
print("ULTIMA_AGREGACION="+json.dumps(last,ensure_ascii=False))
print("CONTEO_6_Y_TOTAL_2100=OK")
PY_AGG
}
verify_dlq() {
  python3 - "$TMP/dlq.jsonl" "$TMP/demo.json" <<'PY_DLQ'
import json
import sys
with open(sys.argv[2],encoding="utf-8") as fh: meta=json.load(fh)
matches=[]
with open(sys.argv[1],encoding="utf-8") as fh:
    for line in fh:
        try: item=json.loads(line)
        except json.JSONDecodeError: continue
        try: original=json.loads(item.get("originalValue") or "{}")
        except (TypeError,ValueError): continue
        if original.get("eventId")==meta["invalidId"]:
            matches.append(item)
assert len(matches)==1, "Se esperaba exactamente un rechazo DLQ"
assert matches[0].get("reason")==meta["expectedReason"], \
    "Motivo DLQ distinto"
print("DLQ_EVENTO_INVALIDO=1")
print("DLQ_REASON="+str(matches[0]["reason"]))
print("DLQ_VERIFICADA=OK")
PY_DLQ
}

echo
echo "=== 6. VERIFICAR AGREGACION REAL (READ_COMMITTED) ==="
: > "$TMP/consumer-stderr.log"
SUCCESS=0
for attempt in $(seq 1 8); do
  read_topic ventas-agregadas 2 "$TMP/aggregate.jsonl"
  if verify_aggregate > "$TMP/check-agg.txt" 2>&1; then
    SUCCESS=1
    echo "AGREGACION_CONFIRMADA_INTENTO=$attempt/8"
    cat "$TMP/check-agg.txt"
    break
  fi
  echo "ESPERANDO_AGREGACION_INTENTO=$attempt/8"
  sleep 3
done
if [[ "$SUCCESS" != "1" ]]; then
  echo "ERROR: no se confirmo agregacion final"
  cat "$TMP/check-agg.txt"
  tail -15 "$TMP/consumer-stderr.log" || true
  exit 1
fi

echo
echo "=== 7. VERIFICAR DLQ REAL (READ_COMMITTED) ==="
SUCCESS=0
for attempt in $(seq 1 5); do
  read_topic ventas-raw-dlq 4 "$TMP/dlq.jsonl"
  if verify_dlq > "$TMP/check-dlq.txt" 2>&1; then
    SUCCESS=1
    cat "$TMP/check-dlq.txt"
    break
  fi
  echo "ESPERANDO_DLQ_INTENTO=$attempt/5"
  sleep 3
done
if [[ "$SUCCESS" != "1" ]]; then
  echo "ERROR: no se confirmo rechazo DLQ"
  cat "$TMP/check-dlq.txt"
  exit 1
fi

echo
echo "=== 8. VERIFICAR DEDUPLICACION EN JOURNALD ==="
DUP_ID=$(python3 - "$TMP/demo.json" <<'PY_DUP'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f: print(json.load(f)["duplicateId"])
PY_DUP
)
FOUND=0
for attempt in $(seq 1 8); do
  LINE=$(app "sudo -n journalctl -u dsy1107-ventas-streams.service --since '@$START_EPOCH' --no-pager -o cat | grep -F 'DUPLICATE_EVENT_ID=$DUP_ID' | tail -1" || true)
  if [[ -n "$LINE" ]]; then
    echo "$LINE"
    FOUND=1
    break
  fi
  sleep 3
done
[[ "$FOUND" == "1" ]] || {
  echo "ERROR: falta evidencia del ID duplicado en Streams"; exit 1;
}
echo "DUPLICADO_EVENTID_DESCARTADO=OK"

echo
echo "=== 9. VALIDAR CAMBIOS EN PROMETHEUS ==="
PROMETHEUS_OK=0
for attempt in $(seq 1 20); do
  snapshot > "$TMP/after.json"
  if python3 - "$TMP/before.json" "$TMP/after.json" <<'PY_DELTA' > "$TMP/check-metrics.txt" 2>&1
import json
import sys
with open(sys.argv[1],encoding="utf-8") as f: before=json.load(f)
with open(sys.argv[2],encoding="utf-8") as f: after=json.load(f)
delta={key:round(after[key]-before[key]) for key in ("raw","aggregated","dlq")}
print("INCREMENTO_RAW="+str(delta["raw"]))
print("INCREMENTO_AGREGADAS="+str(delta["aggregated"]))
print("INCREMENTO_DLQ="+str(delta["dlq"]))
assert after["brokers"]>=2, "Kafka Exporter no detecta ambos brokers"
assert delta["raw"]>=8, "No se observaron los 8 eventos en Raw"
assert delta["aggregated"]>=1, "No se observo salida en Agregadas"
assert delta["dlq"]>=1, "No se observo salida en DLQ"
print("PROMETHEUS_BROKERS=2")
print("PROMETHEUS_DELTAS=OK")
PY_DELTA
  then
    PROMETHEUS_OK=1
    cat "$TMP/check-metrics.txt"
    break
  fi
  if (( attempt % 4 == 0 )); then
    echo "ESPERANDO_SCRAPE_PROMETHEUS=$attempt/20"
  fi
  sleep 5
done
if [[ "$PROMETHEUS_OK" != "1" ]]; then
  echo "ERROR: Prometheus no refleja los incrementos esperados"
  cat "$TMP/check-metrics.txt"
  exit 1
fi

echo
echo "=== 10. VERIFICACION FINAL SIN REINICIOS ==="
[[ "$(app 'systemctl is-active dsy1107-ventas-streams.service')" == "active" ]]
[[ "$(k2 'sudo -n docker inspect -f "{{.State.Running}}" dsy1107-broker-2')" == "true" ]]
echo "STREAMS_FINAL=active"
echo "BROKER2_FINAL=running"
echo "TOPOLOGIA_Y_MONITORING=OK"

echo
echo "=========================================="
echo " DEMOSTRACION INTEGRAL KAFKA + GRAFANA OK"
echo "=========================================="
echo "DEMO_END_TO_END=OK"
echo "OBSERVABILIDAD_EN_VIVO=OK"
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
