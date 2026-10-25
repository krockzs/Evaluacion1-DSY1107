# Pedidos360 backend systemd deployment (EC2 APP)

The five JARs are transferred separately and SHA-256 verified at:
`/home/ubuntu/pedidos360-jars/{bff-service,ot-service,event-service,notification-service,rabbit-admin-service}.jar`.

This directory contains a versioned systemd **template**. Each of the five services gets an independent unit instance. Deploy only after confirming the Oracle database, RabbitMQ Management and Kafka are reachable.

## Environment variables

Before starting, create `/etc/pedidos360/backend.env` directly on EC2 with mode `0600`, owned by root. **Never commit this file.**

It must contain valid credentials for the existing Oracle PDB and RabbitMQ plus the existing Entra settings, as applicable:

- `ORACLE_URL=jdbc:oracle:thin:@//172.31.69.49:1521/FREEPDB1`, `ORACLE_USERNAME`, `ORACLE_PASSWORD`
- `RABBITMQ_HOST=127.0.0.1`, `RABBITMQ_PORT=5672`, `RABBITMQ_USERNAME`, `RABBITMQ_PASSWORD`
- `RABBITMQ_MANAGEMENT_URL=http://127.0.0.1:15672/`, `RABBITMQ_ADMIN_USERNAME`, `RABBITMQ_ADMIN_PASSWORD`
- `KAFKA_BOOTSTRAP_SERVERS=127.0.0.1:9092`
- `ENTRA_ISSUER_URI`, `ENTRA_API_CLIENT_ID`, `ENTRA_JWK_SET_URI`, `FRONTEND_ORIGIN`

The application's existing default values are not a substitute for verifying live credentials. Do not paste secrets into chat or logs.

## Install (not run until configuration is ready)

```bash
sudo install -m 0644 deploy/services/pedidos360@.service /etc/systemd/system/pedidos360@.service
sudo systemctl daemon-reload
# Example, one instance at a time:
sudo systemctl enable --now pedidos360@ot-service.service
sudo systemctl status pedidos360@ot-service.service --no-pager
```

Other instances: `event-service`, `notification-service`, `rabbit-admin-service`, `bff-service`. The systemd template limits each JVM heap to 320 MiB plus a 160 MiB metaspace cap; verify actual memory during staged startup on the 4 GiB instance.
