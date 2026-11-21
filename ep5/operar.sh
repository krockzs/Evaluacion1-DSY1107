#!/usr/bin/env bash
set -Eeuo pipefail

# Consola operativa EP5 para el Ryzen. No ejecuta servicios en local.
# Los cambios de estado se hacen solamente con scripts explicitos.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/ep5"
PEM="$HOME/Downloads/Pedidos360-Key.pem"
AWS_PROFILE="pedidos360"
AWS_REGION="us-east-1"
CFG=""
export AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off

cleanup() {
  if [[ -n "$CFG" ]]; then
    rm -f "$CFG"
  fi
}
trap cleanup EXIT

ayuda() {
  cat <<'AYUDA'
DSY1107 EP5 - CONSOLA DE OPERACION (Ryzen / NEEBLES OS)

  bash ep5/operar.sh ayuda            Muestra todos los comandos
  bash ep5/operar.sh estado           EC2, servicios y contenedores
  bash ep5/operar.sh kafka-ui         Kafka UI: http://127.0.0.1:18080
  bash ep5/operar.sh grafana          Grafana: http://127.0.0.1:3000/d/dsy1107-kafka-ep5
  bash ep5/operar.sh prometheus       Prometheus: http://127.0.0.1:19090
  bash ep5/operar.sh topicos          Lista y estado de topicos Kafka
  bash ep5/operar.sh grupos           Grupo de consumidores Streams
  bash ep5/operar.sh configs          Abre configs versionadas en Kate
  bash ep5/operar.sh configs-vivas    Consulta configuracion real desplegada
  bash ep5/operar.sh ssh-app          SSH interactivo hacia APP
  bash ep5/operar.sh ssh-kafka1       SSH interactivo hacia broker 1
  bash ep5/operar.sh ssh-kafka2       SSH interactivo hacia broker 2
  bash ep5/operar.sh ssh-monitoring   SSH interactivo hacia Monitoring
  bash ep5/operar.sh prueba demo      Demo real, agrega 8 eventos ficticios
  bash ep5/operar.sh prueba tardios   4 tests Maven, sin afectar topicos
  bash ep5/operar.sh prueba failover  DETIENE y recupera broker 2
  bash ep5/operar.sh prueba estado    Auditoria de metricas Prometheus
  bash ep5/operar.sh prueba persistencia  REINICIA Kafka Streams
  bash ep5/operar.sh prueba postboot  REINICIA EC2 Monitoring
  bash ep5/operar.sh ultimo           Abre ultimo TXT DSY1107 en Kate

Importante:
- Los tuneles Kafka UI, Grafana y Prometheus usan UNA TERMINAL CADA UNO.
- Mantener la terminal abierta. Ctrl+C cierra el tunel.
- En pruebas disruptivas se pide confirmacion.
- No usar el script de failover durante otra prueba simultanea.
- El archivo principal README.md corresponde a una evaluacion anterior.
- Manual especifico de EP5: ep5/GUIA_OPERATIVA_CLASE.md
AYUDA
}

require_aws() {
  command -v aws >/dev/null || { echo "ERROR: AWS CLI no disponible"; exit 1; }
}
setup_ssh() {
  require_aws
  command -v ssh >/dev/null || { echo "ERROR: no hay cliente SSH"; exit 1; }
  [[ -s "$PEM" ]] || { echo "ERROR: no existe $PEM"; exit 1; }
  chmod 600 "$PEM"

  local app_ip monitor_ip
  app_ip=$(aws ec2 describe-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids i-09732ce35a9b0e22b \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  monitor_ip=$(aws ec2 describe-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids i-0e3af62685c90f028 \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
  [[ -n "$app_ip" && "$app_ip" != "None" ]] || {
    echo "ERROR: APP sin IP publica. Comprueba que las EC2 esten encendidas."; exit 1;
  }
  [[ "$monitor_ip" == "172.31.69.49" ]] || {
    echo "ERROR: IP privada de Monitoring inesperada"; exit 1;
  }
  CFG=$(mktemp)
  chmod 600 "$CFG"
  cat > "$CFG" <<EOF_SSH
Host app
 HostName $app_ip
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
 HostName $monitor_ip
 User ubuntu
 IdentityFile $PEM
 IdentitiesOnly yes
 BatchMode yes
 ProxyJump app
 ConnectTimeout 15
 ServerAliveInterval 30
 ServerAliveCountMax 3
EOF_SSH
}

status_ec2() {
  require_aws
  echo "=== ESTADO AWS DE LAS 4 EC2 ==="
  aws ec2 describe-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids \
      i-09732ce35a9b0e22b \
      i-007b3c21d4d0decea \
      i-00ac1f46c3ddd6c04 \
      i-0e3af62685c90f028 \
    --query 'Reservations[].Instances[].{ID:InstanceId,Estado:State.Name,Privada:PrivateIpAddress,Publica:PublicIpAddress}' \
    --output table
  echo
  echo "=== SERVICIOS (si APP esta accesible) ==="
  if ! setup_ssh; then
    echo "SSH_NO_DISPONIBLE: comprueba encendido/credenciales"
    return 0
  fi
  ssh -n -F "$CFG" app \
    'systemctl is-active dsy1107-ventas-streams.service' \
    || echo "STREAMS=NO_VERIFICADO"
  for host in kafka1 kafka2; do
    container="dsy1107-broker-1"
    if [[ "$host" == "kafka2" ]]; then container="dsy1107-broker-2"; fi
    printf '%s: ' "$host"
    ssh -n -F "$CFG" "$host" \
      "sudo -n docker inspect -f '{{.State.Status}}' $container" \
      || echo "NO_VERIFICADO"
  done
  ssh -n -F "$CFG" monitoring \
    "sudo -n docker ps --format 'CONTENEDOR={{.Names}} ESTADO={{.Status}} PUERTOS={{.Ports}}'" \
    || echo "MONITORING=NO_VERIFICADO"
}

tunel() {
  local servicio="$1"
  setup_ssh
  case "$servicio" in
    kafka-ui)
      echo "Kafka UI: http://127.0.0.1:18080"
      echo "Deja esta terminal abierta; Ctrl+C para cerrar."
      ssh -N -F "$CFG" -o ExitOnForwardFailure=yes \
        -L 127.0.0.1:18080:172.31.91.91:8080 app
      ;;
    prometheus)
      echo "Prometheus: http://127.0.0.1:19090"
      echo "Deja esta terminal abierta; Ctrl+C para cerrar."
      ssh -N -F "$CFG" -o ExitOnForwardFailure=yes \
        -L 127.0.0.1:19090:127.0.0.1:9090 monitoring
      ;;
  esac
}

topicos() {
  setup_ssh
  echo "=== TOPICOS DISPONIBLES ==="
  ssh -n -F "$CFG" kafka2 \
    'sudo -n docker exec dsy1107-broker-2 kafka-topics --bootstrap-server localhost:9092 --list'
  echo
  for topic in ventas-raw ventas-agregadas ventas-raw-dlq; do
    echo "=== CONFIGURACION TOPICO $topic ==="
    ssh -n -F "$CFG" kafka2 \
      "sudo -n docker exec dsy1107-broker-2 kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic"
  done
}

grupos() {
  setup_ssh
  ssh -n -F "$CFG" kafka2 \
    'sudo -n docker exec dsy1107-broker-2 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams'
}

configs_local() {
  command -v kate >/dev/null || { echo "ERROR: falta Kate"; exit 1; }
  kate \
    "$BASE/app/streams/.env.example" \
    "$BASE/app/streams/deploy/dsy1107-ventas-streams.service" \
    "$BASE/monitoring/compose.yaml" \
    "$BASE/monitoring/prometheus/prometheus.yml" \
    "$BASE/monitoring/grafana/provisioning/datasources/prometheus.yaml" \
    "$BASE/monitoring/grafana/provisioning/dashboards/default.yaml" \
    "$BASE/GUIA_OPERATIVA_CLASE.md"
  echo "CONFIGS_VERSIONADAS=ABIERTAS"
}

configs_vivas() {
  setup_ssh
  echo "=== APP: SERVICIO STREAMS ==="
  ssh -n -F "$CFG" app \
    'systemctl show dsy1107-ventas-streams.service -p ActiveState -p UnitFileState -p FragmentPath -p ExecStart -p Restart -p User -p EnvironmentFiles'
  echo
  echo "=== APP: VARIABLES DE STREAMS (SOLO CAMPOS NO SECRETOS) ==="
  ssh -n -F "$CFG" app \
    'grep -E "^(KAFKA_APPLICATION_ID|KAFKA_BOOTSTRAP_SERVERS|KAFKA_STATE_DIR)=" /home/ubuntu/dsy1107-ep5/streams/.env || true'
  echo
  for spec in 'kafka1:1' 'kafka2:2'; do
    host=$(printf '%s' "$spec" | cut -d: -f1)
    broker=$(printf '%s' "$spec" | cut -d: -f2)
    echo "=== BROKER $broker: CONFIGURACION DOCKER SELECCIONADA ==="
    ssh -n -F "$CFG" "$host" \
      "sudo -n docker inspect -f '{{.Name}} {{.State.Status}} {{.HostConfig.RestartPolicy.Name}}' dsy1107-broker-$broker"
    ssh -n -F "$CFG" "$host" \
      "sudo -n docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' dsy1107-broker-$broker | grep -E '^(KAFKA_(BROKER_ID|LISTENERS|ADVERTISED_LISTENERS|DEFAULT_REPLICATION_FACTOR|MIN_INSYNC_REPLICAS|OFFSETS_TOPIC_REPLICATION_FACTOR|TRANSACTION_STATE_LOG_REPLICATION_FACTOR|TRANSACTION_STATE_LOG_MIN_ISR))=' || true"
  done
  echo
  echo "=== MONITORING: CONFIGURACION DESPLEGADA ==="
  ssh -n -F "$CFG" monitoring \
    'cd /home/ubuntu/dsy1107-ep5/monitoring && sudo -n docker compose -f compose.yaml ps && cat prometheus/prometheus.yml'
  echo
  echo "Nota: claves/secretos de Grafana no se imprimen."
}

confirmar() {
  local palabra="$1" descripcion="$2" respuesta
  echo "ATENCION: $descripcion"
  printf 'Para continuar, escribe %s: ' "$palabra"
  read -r respuesta
  [[ "$respuesta" == "$palabra" ]] || {
    echo "CANCELADO: no se ejecuto el paso disruptivo."
    exit 2
  }
}

prueba() {
  local tipo="$1" script=""
  case "$tipo" in
    demo) script="$BASE/tests/demo-integral-monitoring.sh" ;;
    tardios) script="$BASE/tests/eventos-tardios.sh" ;;
    failover)
      confirmar FAILOVER "Se detendra temporalmente Kafka-2 y se intentara recuperarlo."
      script="$BASE/tests/failover-kafka.sh"
      ;;
    persistencia)
      confirmar STREAMS "Se reiniciara el servicio Kafka Streams para probar persistencia."
      script="$BASE/tests/persistencia-streams.sh"
      ;;
    postboot)
      confirmar REINICIO "Se reiniciara la EC2 Monitoring en AWS."
      script="$BASE/monitoring/certificar-post-reinicio.sh"
      ;;
    estado) script="$BASE/monitoring/auditar-metricas.sh" ;;
    *) ayuda; exit 2 ;;
  esac
  [[ -s "$script" ]] || { echo "ERROR: no existe $script"; exit 1; }
  bash -n "$script"
  echo "=== EJECUTANDO: $script ==="
  bash "$script"
}

ultimo() {
  command -v kate >/dev/null || { echo "ERROR: falta Kate"; exit 1; }
  local path
  path=$(find /tmp -maxdepth 1 -type f -name 'DSY1107_*.txt' \
    -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
  [[ -n "$path" && -f "$path" ]] || {
    echo "ERROR: no existe ningun TXT de DSY1107 en /tmp"; exit 1;
  }
  echo "INFORME=$path"
  kate "$path"
}

main() {
  local cmd="$1"
  case "$cmd" in
    ayuda|-h|--help) ayuda ;;
    estado) status_ec2 ;;
    kafka-ui) tunel kafka-ui ;;
    prometheus) tunel prometheus ;;
    grafana) bash "$BASE/monitoring/abrir-grafana.sh" ;;
    topicos) topicos ;;
    grupos) grupos ;;
    configs) configs_local ;;
    configs-vivas) configs_vivas ;;
    ssh-app) setup_ssh; ssh -F "$CFG" app ;;
    ssh-kafka1) setup_ssh; ssh -F "$CFG" kafka1 ;;
    ssh-kafka2) setup_ssh; ssh -F "$CFG" kafka2 ;;
    ssh-monitoring) setup_ssh; ssh -F "$CFG" monitoring ;;
    prueba) prueba "$2" ;;
    ultimo) ultimo ;;
    *) echo "ERROR: comando desconocido: $cmd"; ayuda; exit 2 ;;
  esac
}

main "$@" 
