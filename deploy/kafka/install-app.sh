#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
test -x /opt/kafka/bin/kafka-storage.sh || { echo "Missing Kafka in /opt/kafka"; exit 1; }
command -v java >/dev/null
sudo install -d -m 0755 /etc/kafka
sudo install -d -o ubuntu -g ubuntu -m 0750 /var/lib/kafka/data
sudo install -m 0644 server.properties /etc/kafka/pedidos360.properties
sudo install -m 0644 pedidos360-kafka.service /etc/systemd/system/pedidos360-kafka.service
if [ -f /var/lib/kafka/data/meta.properties ]; then
  echo "Kafka storage already initialized; preserving data."
elif [ -z "$(find /var/lib/kafka/data -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "Initializing new empty Kafka KRaft storage"
  cluster_id="$(/opt/kafka/bin/kafka-storage.sh random-uuid)"
  /opt/kafka/bin/kafka-storage.sh format --standalone -t "$cluster_id" -c /etc/kafka/pedidos360.properties
else
  echo "ABORT: nonempty Kafka storage without meta.properties" >&2
  exit 1
fi
sudo systemctl daemon-reload
sudo systemctl enable --now pedidos360-kafka.service
systemctl --no-pager --full status pedidos360-kafka.service || true
