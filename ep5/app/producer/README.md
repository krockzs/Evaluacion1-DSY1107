# DSY1107 - EP5 Producer Java 21

Productor académico de eventos de ventas para Apache Kafka.

## Contrato JSON

- eventId: UUID
- eventTime: instante UTC ISO-8601
- customerId: identificador de cliente
- store: identificador de tienda
- price: número decimal
- quantity: cantidad entera

La clave Kafka corresponde a customerId.

## Compilación

Ejecutar: mvn clean verify

## Configuración

KAFKA_BOOTSTRAP_SERVERS=172.31.91.91:9092,172.31.27.158:9092

KAFKA_TOPIC=ventas-raw

## Ejecución

Ejecutar: java -jar target/ventas-producer-1.0.0.jar 3

El productor utiliza acks=all e idempotencia habilitada.

La deduplicación lógica por eventId se implementará
posteriormente en el procesador Kafka Streams.
