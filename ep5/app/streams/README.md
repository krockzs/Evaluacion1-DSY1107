# DSY1107 EP5 — Kafka Streams Java 21

Procesador de ventas para el clúster de dos brokers (Kafka 3.6.x, ZooKeeper).

## Flujo

ventas-raw -> validación -> repartición por eventId -> estado persistente de deduplicación -> agrupación por tienda -> ventanas de 1 minuto -> ventas-agregadas.

Los eventos inválidos se publican en ventas-raw-dlq, conservando originalTopic, originalKey, originalValue y reason.

## Garantías y decisiones

- Exactly-once-v2: atomicidad transaccional entre offsets, cambios de estado y salidas Kafka.
- Deduplicación explícita: store RocksDB persistente ventas-eventid-dedup, con changelog de Kafka. Repartición por eventId para evitar duplicados con claves de cliente diferentes.
- Ventanas tumbling de 60 segundos, gracia de 30 segundos. La hora se obtiene del campo eventTime, no de la llegada.
- Eventos tardíos dentro de la gracia: se agregan. Tras el cierre de la ventana: Kafka Streams los descarta de esa agregación; la información se mantiene en ventas-raw. Se investigarán las métricas de registros descartados.
- Resultado: cada actualización emite JSON con store, windowStart, windowEnd, saleCount y totalAmount.
- El store de deduplicación no tiene expiración en esta versión de laboratorio; requiere política TTL/compactación antes de cargas grandes.
- Un solo proceso Streams corre en APP; la recuperación del estado depende de sus changelogs de Kafka.
- Kafka-1 aloja un único ZooKeeper: es punto único de fallo en la arquitectura de laboratorio.

## Compilar y probar

mvn --batch-mode clean verify

## Ejecutar

KAFKA_APPLICATION_ID=dsy1107-ventas-streams
KAFKA_BOOTSTRAP_SERVERS=172.31.91.91:9092,172.31.27.158:9092
KAFKA_STATE_DIR=/home/ubuntu/dsy1107-ep5/state
java -jar target/ventas-streams-1.0.0.jar

No almacenes secretos en el repositorio.
