# Evaluación 1 — DSY1107 Desarrollo Cloud Native I

Implementación base del sistema solicitado en la Evaluación Parcial N.º 1, construida a partir de los dos insumos oficiales del encargo:

- pauta de evaluación: Angular + MSAL, Spring Boot, BFF, JWT, API Gateway, EC2 y base de datos cloud;
- `Script.sql`: modelo TALLERPRO360 con `OT`, `OT_ITEM`, `OT_EVENT`, `NOTIFY_LOG` y `V_OT_RESUMEN`, además de Kafka y RabbitMQ.

## Estructura

```text
Evaluacion1/
├── backend/
│   ├── bff-service/             # Entrada para Angular + validación JWT/roles/scopes
│   ├── ot-service/              # OT + OT_ITEM + V_OT_RESUMEN
│   ├── event-service/           # Consume Kafka y persiste OT_EVENT
│   └── notification-service/    # Consume RabbitMQ y persiste NOTIFY_LOG
├── frontend/
│   └── pedidos360-web/          # Angular + MSAL
└── database/
    └── Script.sql               # Script oficial entregado
```

## Puertos locales

| Componente | Puerto |
|---|---:|
| Angular | 4200 |
| BFF | 8080 |
| OT Service | 8081 |
| Event Service | 8082 |
| Notification Service | 8083 |
| Oracle | 1521 |
| Kafka | 9092 |
| RabbitMQ | 5672 |

## Variables principales

Los servicios usan variables de entorno para evitar secretos en GitHub.

```text
ORACLE_URL=jdbc:oracle:thin:@//localhost:1521/FREEPDB1
ORACLE_USERNAME=TALLERPRO360
ORACLE_PASSWORD=ChangeMe_2025!

ENTRA_TENANT_ID=<tenant-id>
ENTRA_API_CLIENT_ID=<application-client-id-de-la-api>
ENTRA_ISSUER_URI=https://login.microsoftonline.com/<tenant-id>/v2.0

OT_SERVICE_URL=http://localhost:8081
EVENT_SERVICE_URL=http://localhost:8082
NOTIFICATION_SERVICE_URL=http://localhost:8083

KAFKA_BOOTSTRAP_SERVERS=localhost:9092
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USERNAME=guest
RABBITMQ_PASSWORD=guest
```

## Flujo

```text
Angular + MSAL
      |
      | Bearer JWT
      v
     BFF :8080
      |
      +------> OT Service :8081 ------> Oracle (OT, OT_ITEM, V_OT_RESUMEN)
      |
      +------> Event Service :8082 ---> Oracle (OT_EVENT)
      |
      +------> Notification Service ---> Oracle (NOTIFY_LOG)

OT Service --Kafka--> Event Service
OT Service --RabbitMQ--> Notification Service
```

En AWS el API Gateway queda delante del BFF y valida el JWT en el borde. El BFF vuelve a validarlo, porque eso se exige expresamente en la pauta.

## Orden sugerido de ejecución local

1. Ejecutar `database/Script.sql` en Oracle.
2. Tener Kafka y RabbitMQ disponibles.
3. Levantar `ot-service`, `event-service`, `notification-service` y `bff-service`.
4. Completar los valores de Microsoft Entra en `frontend/pedidos360-web/src/environments/environment.ts`.
5. Ejecutar Angular con `npm install` y `npm start`.

## Importante

No se incluyen Terraform, Docker, Kubernetes, ECS ni Lambda en esta etapa. La infraestructura como código puede agregarse después, una vez validada manualmente la solución académica.
