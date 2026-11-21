# DSY1107 · EP6 — Arquitectura implementada y conexiones reales

Diagrama de la solución Kafka de la evaluación EP6, correspondiente a la rama `ep5-app`. No representa el sistema Angular/Oracle de evaluaciones anteriores.

```mermaid
flowchart LR
    R["🔴 Ryzen · NEEBLES OS<br/>Venta JSON editable en Kate<br/>Terminal SSH / Firefox"]
    A["EC2 APP<br/>172.31.25.21<br/>Java 21 · Kafka Streams<br/>systemd / RocksDB"]
    B1["EC2 Kafka-1<br/>172.31.91.91<br/>Broker 1<br/>ZooKeeper único / Kafka UI"]
    B2["EC2 Kafka-2<br/>172.31.27.158<br/>Broker 2"]
    RAW[("ventas-raw<br/>4 particiones · RF=2")]
    AGG[("ventas-agregadas<br/>2 particiones · RF=2")]
    DLQ[("ventas-raw-dlq<br/>4 particiones · RF=2")]
    MON["EC2 Monitoring<br/>172.31.69.49<br/>Kafka Exporter"]
    P["Prometheus<br/>Scrape cada 15 s"]
    G["Grafana<br/>15 paneles"]
    Z["ZooKeeper<br/>Punto único de fallo"]

    R -->|"SSH por APP al broker 2<br/>console-producer · acks=all"| B2
    B1 <-->|"Réplicas e ISR<br/>RF=2"| B2
    B1 --- RAW
    B2 --- RAW
    RAW -->|"Consumo y offsets<br/>grupo dsy1107-ventas-streams"| A
    A -->|"Válidos, deduplicación eventId<br/>ventanas de 60 s + gracia de 30 s"| AGG
    A -->|"Inválidos: original + motivo"| DLQ
    Z --- B1
    MON -.->|"Consulta 9092"| B1
    MON -.->|"Consulta 9092"| B2
    MON --> P
    P --> G
    R -.->|"Túnel SSH privado:18080"| B1
    R -.->|"Túnel SSH privado:3000"| G
```

## Decisiones que se deben defender

- **Dos brokers:** permiten RF=2, no RF=3; con `min.insync.replicas=1` el laboratorio puede aceptar escrituras durante la caída de uno, a costa de menor redundancia mientras se reconstituye el ISR.
- **ZooKeeper único en Kafka-1:** es un riesgo conocido, por lo que no se afirma alta disponibilidad total del clúster.
- **Kafka Streams en APP:** procesa `ventas-raw`, rechaza JSON inválidos hacia DLQ, reagrupa por `eventId`, deduplica con estado persistente (RocksDB y changelog), y emite agregados por tienda/ventana.
- **Exactly-once-v2:** protege el procesamiento transaccional de offsets/estado/salidas, pero no reemplaza deduplicación de negocio con `eventId`.
- **Ventanas:** 1 minuto + 30 segundos de gracia, aplicadas al `eventTime` del mensaje; un evento válido demasiado tardío se descarta de la agregación, no va a DLQ.
- **Monitoring:** Kafka Exporter consulta brokers, Prometheus captura cada 15 segundos y Grafana visualiza los resultados. No se presenta el lag o los offsets como cifras exclusivas de una venta.
- **Seguridad de acceso:** Kafka UI/Grafana se ven desde Firefox en Ryzen mediante SSH; no abrir puertos administrativos públicamente.

**Nota:** la pauta menciona `arquitectura_encargo.mmd` como diagrama objetivo proporcionado en clases. Ese archivo no se encuentra en esta rama del repositorio. Este diagrama documenta lo implementado; es necesario compararlo con el diagrama original cuando esté disponible.
