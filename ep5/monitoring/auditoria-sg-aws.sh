#!/usr/bin/env bash
set -Eeuo pipefail

REPORT="/tmp/DSY1107_AUDITORIA_SG_$(date +%Y%m%d_%H%M%S).txt"
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off
command -v aws >/dev/null
command -v python3 >/dev/null

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
exec > >(tee "$REPORT") 2>&1
trap 'echo "AUDITORIA_INCOMPLETA=SI; INFORME=$REPORT"' ERR

echo "=========================================="
echo " DSY1107 - AUDITORIA SECURITY GROUPS"
echo "=========================================="
date

echo
echo "=== 1. CONSULTAR LAS CUATRO EC2 ==="
aws ec2 describe-instances \
  --profile pedidos360 --region us-east-1 \
  --instance-ids \
    i-09732ce35a9b0e22b \
    i-007b3c21d4d0decea \
    i-00ac1f46c3ddd6c04 \
    i-0e3af62685c90f028 \
  --output json > "$TMP/instances.json"

GROUP_LIST=$(python3 - "$TMP/instances.json" <<'PY_GROUPS'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data=json.load(handle)
instances=[x for r in data["Reservations"] for x in r["Instances"]]
assert len(instances)==4, "Deben existir las cuatro EC2"
for x in sorted(instances, key=lambda v:v["InstanceId"]):
    assert x["State"]["Name"]=="running", "EC2 no esta running"
    print("EC2={0} IP={1} VPC={2} SUBNET={3} SG={4}".format(
        x["InstanceId"], x.get("PrivateIpAddress"), x.get("VpcId"),
        x.get("SubnetId"),
        ",".join(s["GroupId"] for s in x["SecurityGroups"])
    ), file=sys.stderr)
print(" ".join(sorted({
    s["GroupId"] for x in instances for s in x["SecurityGroups"]
})))
PY_GROUPS
)
[[ -n "$GROUP_LIST" ]] || {
  echo "ERROR: no se obtuvieron grupos de seguridad"; exit 1;
}

echo
echo "=== 2. CONSULTAR REGLAS AWS (SOLO LECTURA) ==="
# IDs generados por AWS: solo contienen el patron sg-hex.
for group in $GROUP_LIST; do
  [[ "$group" =~ ^sg-[0-9a-f]+$ ]] || {
    echo "ERROR: SG no valido"; exit 1;
  }
done

aws ec2 describe-security-groups \
  --profile pedidos360 --region us-east-1 \
  --group-ids $GROUP_LIST --output json \
  > "$TMP/groups.json"

python3 - "$TMP/instances.json" "$TMP/groups.json" <<'PY_AUDIT'
import ipaddress
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data=json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    sg_data=json.load(handle)

instances={x["InstanceId"]:x for r in data["Reservations"]
           for x in r["Instances"]}
sg={g["GroupId"]:g for g in sg_data["SecurityGroups"]}
mon=instances["i-0e3af62685c90f028"]
mon_sg={g["GroupId"] for g in mon["SecurityGroups"]}
mon_ip=ipaddress.ip_address(mon["PrivateIpAddress"])

def permitted(rule, source_sg, source_ip, port):
    proto=str(rule.get("IpProtocol", ""))
    if proto not in ("-1", "tcp", "6"):
        return False
    if proto != "-1":
        if not (int(rule.get("FromPort", 65536)) <= port
                <= int(rule.get("ToPort", -1))):
            return False
    if any(g.get("GroupId") in source_sg
           for g in rule.get("UserIdGroupPairs", [])):
        return True
    for entry in rule.get("IpRanges", []):
        cidr=entry.get("CidrIp")
        if cidr and source_ip in ipaddress.ip_network(cidr, strict=False):
            return True
    return False

def allows(sg_ids, rule_field, peers, peer_ip, port):
    return any(permitted(rule, peers, peer_ip, port)
               for group in sg_ids
               for rule in sg[group].get(rule_field, []))

def print_rules(group_ids, field):
    for group in sorted(group_ids):
        print("SG={0} DIRECCION={1}".format(
            group, "INGRESS" if field=="IpPermissions" else "EGRESS"))
        rules=sg[group].get(field, [])
        if not rules:
            print("  SIN_REGLAS")
        for rule in rules:
            proto=rule.get("IpProtocol", "-")
            ports=("ALL" if proto=="-1" else
                   str(rule.get("FromPort"))+"-"+str(rule.get("ToPort")))
            peers=([g.get("GroupId") for g in rule.get("UserIdGroupPairs", [])] +
                   [g.get("CidrIp") for g in rule.get("IpRanges", [])] +
                   [g.get("CidrIpv6") for g in rule.get("Ipv6Ranges", [])])
            print("  PROTO={0} PUERTOS={1} PEERS={2}".format(
                proto, ports, ",".join(str(p) for p in peers)))

print("")
print("=== 3. REGLAS DE ENTRADA EN BROKERS ===")
for label, ident in [
    ("KAFKA1", "i-007b3c21d4d0decea"),
    ("KAFKA2", "i-00ac1f46c3ddd6c04")
]:
    broker=instances[ident]
    broker_sg={g["GroupId"] for g in broker["SecurityGroups"]}
    broker_ip=ipaddress.ip_address(broker["PrivateIpAddress"])
    print("--- "+label+" ---")
    print_rules(broker_sg, "IpPermissions")
    incoming=allows(broker_sg, "IpPermissions", mon_sg, mon_ip, 9092)
    outgoing=allows(mon_sg, "IpPermissionsEgress",
                    broker_sg, broker_ip, 9092)
    print(label+"_INGRESS_9092_DESDE_MON="+(
        "PERMITIDO" if incoming else "BLOQUEADO"))
    print("MON_EGRESS_9092_HACIA_"+label+"="+(
        "PERMITIDO" if outgoing else "BLOQUEADO"))

print("")
print("=== 4. REGLAS DE SALIDA EN MONITORING ===")
print_rules(mon_sg, "IpPermissionsEgress")
print("MONITORING_SG="+",".join(sorted(mon_sg)))
print("MISMA_VPC="+(
    "SI" if len({i["VpcId"] for i in instances.values()})==1 else "NO"))
print("NOTA=Evaluacion SG; no incluye NACL, rutas o firewall del SO")
print("AUDITORIA_SG=OK")
PY_AUDIT

echo
echo "=========================================="
echo " AUDITORIA COMPLETA - SIN MODIFICACIONES"
echo "=========================================="
echo "RESULTADO=OK"
echo "INFORME=$REPORT"
