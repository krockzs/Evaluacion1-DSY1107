#!/usr/bin/env bash
set -Eeuo pipefail

BROKER_SG="sg-04509723b6cdea529"
MON_SG="sg-04a36e10adc053871"
EXPECTED_VPC="vpc-0eaa5603256f0610f"
PEM="$HOME/Downloads/Pedidos360-Key.pem"
REPORT="/tmp/DSY1107_MONITORING_RED_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off
command -v aws >/dev/null
command -v python3 >/dev/null
[[ -s "$PEM" ]] || { echo "ERROR: PEM no encontrada"; exit 1; }
chmod 600 "$PEM"

TMP=$(mktemp -d)
CFG="$TMP/ssh_config"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT
exec > >(tee "$REPORT") 2>&1
trap 'echo "PROCEDIMIENTO_INCOMPLETO=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - ACCESO PRIVADO MONITORING/KAFKA"
echo "=========================================="
date

echo
echo "=== 1. VALIDAR EC2 Y SECURITY GROUPS ==="
aws ec2 describe-instances --profile pedidos360 --region us-east-1 \
 --instance-ids i-09732ce35a9b0e22b i-0e3af62685c90f028 \
   i-007b3c21d4d0decea i-00ac1f46c3ddd6c04 \
 --output json > "$TMP/instances.json"

aws ec2 describe-security-groups --profile pedidos360 --region us-east-1 \
 --group-ids "$BROKER_SG" "$MON_SG" --output json > "$TMP/sg.json"

python3 - "$TMP/instances.json" "$TMP/sg.json" \
 "$BROKER_SG" "$MON_SG" "$EXPECTED_VPC" <<'PY_CHECK'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data=json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    groups=json.load(handle)
broker_sg, mon_sg, vpc=sys.argv[3:]
ec2={i["InstanceId"]:i for r in data["Reservations"] for i in r["Instances"]}
expected={
    "i-09732ce35a9b0e22b": None,
    "i-0e3af62685c90f028": mon_sg,
    "i-007b3c21d4d0decea": broker_sg,
    "i-00ac1f46c3ddd6c04": broker_sg
}
assert set(ec2)==set(expected), "Instancias distintas de las esperadas"
for identifier, group in expected.items():
    obj=ec2[identifier]
    assert obj["State"]["Name"]=="running", "Instancia detenida"
    assert obj["VpcId"]==vpc, "Instancia fuera de la VPC"
    if group:
        assert group in {x["GroupId"] for x in obj["SecurityGroups"]}, \
            "SG distinto en la instancia"
    print("INSTANCIA_VERIFICADA="+identifier)
for group in groups["SecurityGroups"]:
    assert group["VpcId"]==vpc, "Security Group fuera de la VPC"
print("MISMA_VPC=OK")
print("SG_VERIFICADOS=OK")
PY_CHECK

echo
echo "=== 2. REGLA EXCLUSIVA DE MONITORING AL PUERTO 9092 ==="
if python3 - "$TMP/sg.json" "$BROKER_SG" "$MON_SG" <<'PY_PRESENT'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    sg=json.load(handle)
broker=next(g for g in sg["SecurityGroups"] if g["GroupId"]==sys.argv[2])
source=sys.argv[3]
found=any(
    rule.get("IpProtocol") in ("tcp","-1") and
    (rule.get("IpProtocol")=="-1" or
     (rule.get("FromPort",65536)<=9092<=rule.get("ToPort",-1))) and
    any(peer.get("GroupId")==source
        for peer in rule.get("UserIdGroupPairs",[]))
    for rule in broker["IpPermissions"]
)
sys.exit(0 if found else 1)
PY_PRESENT
then
  echo "REGLA_PRIVADA_YA_EXISTE=OK"
else
  echo "AUTORIZANDO_TCP_9092_DESDE_MONITORING..."
  aws ec2 authorize-security-group-ingress \
    --profile pedidos360 --region us-east-1 \
    --group-id "$BROKER_SG" --protocol tcp --port 9092 \
    --source-group "$MON_SG" --output json
  echo "REGLA_AWS_CREADA=OK"
fi

echo
echo "=== 3. VERIFICAR NUEVA REGLA AWS ==="
aws ec2 describe-security-groups --profile pedidos360 --region us-east-1 \
 --group-ids "$BROKER_SG" \
 --query 'SecurityGroups[0].IpPermissions' --output json \
 > "$TMP/permissions.json"
python3 - "$TMP/permissions.json" "$MON_SG" <<'PY_VERIFY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    permissions=json.load(handle)
mon=sys.argv[2]
matched=any(
    x.get("IpProtocol")=="tcp" and
    x.get("FromPort")<=9092<=x.get("ToPort") and
    any(v.get("GroupId")==mon for v in x.get("UserIdGroupPairs",[]))
    for x in permissions
)
assert matched, "Regla no encontrada"
print("REGLA_9092_PRIVADA_VERIFICADA=OK")
PY_VERIFY

echo
echo "=== 4. COMPROBAR CONECTIVIDAD DESDE MONITORING ==="
APP_IP=$(python3 - "$TMP/instances.json" <<'PY_APP'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data=json.load(handle)
for reservation in data["Reservations"]:
    for obj in reservation["Instances"]:
        if obj["InstanceId"]=="i-09732ce35a9b0e22b":
            print(obj["PublicIpAddress"])
PY_APP
)

cat > "$CFG" <<EOF_SSH
Host app
 HostName $APP_IP
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
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

ssh -T -F "$CFG" monitoring 'bash -s' <<'REMOTE_TEST'
set -Eeuo pipefail
TOKEN=$(curl -fsS -m 5 -X PUT \
 -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
 http://169.254.169.254/latest/api/token)
ID=$(curl -fsS -m 5 -H "X-aws-ec2-metadata-token: $TOKEN" \
 http://169.254.169.254/latest/meta-data/instance-id)
[[ "$ID" == "i-0e3af62685c90f028" ]] || {
 echo "ERROR: instancia Monitoring incorrecta"; exit 1;
}
echo "IDENTIDAD_MONITORING=OK"
for ip in 172.31.91.91 172.31.27.158; do
 if timeout 7 bash -c "echo >/dev/tcp/$ip/9092" 2>/dev/null; then
   echo "KAFKA_$ip:9092=OPEN"
 else
   echo "KAFKA_$ip:9092=CLOSED_OR_FILTERED"
   exit 1
 fi
done
echo "CONEXION_MONITORING_KAFKA=OK"
REMOTE_TEST

echo
echo "=========================================="
echo " ACCESO PRIVADO A KAFKA CONFIGURADO"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
