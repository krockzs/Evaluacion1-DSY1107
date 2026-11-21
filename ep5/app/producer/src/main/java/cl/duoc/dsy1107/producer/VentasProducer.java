package cl.duoc.dsy1107.producer;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.StringSerializer;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

public final class VentasProducer {

    private VentasProducer() {}

    public static void main(String[] args) throws Exception {

        String bootstrap = requiredEnv("KAFKA_BOOTSTRAP_SERVERS");
        String topic = requiredEnv("KAFKA_TOPIC");

        int count = args.length == 0
            ? 3
            : Integer.parseInt(args[0]);

        if (count < 1 || count > 100) {
            throw new IllegalArgumentException(
                "La cantidad debe estar entre 1 y 100"
            );
        }

        Properties props = new Properties();

        props.put(
            ProducerConfig.BOOTSTRAP_SERVERS_CONFIG,
            bootstrap
        );

        props.put(
            ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG,
            StringSerializer.class.getName()
        );

        props.put(
            ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
            StringSerializer.class.getName()
        );

        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.RETRIES_CONFIG, 5);
        props.put(
            ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION,
            5
        );

        props.put(
            ProducerConfig.CLIENT_ID_CONFIG,
            "dsy1107-ventas-producer"
        );

        ObjectMapper json = new ObjectMapper();

        try (
            KafkaProducer<String, String> producer =
                new KafkaProducer<>(props)
        ) {

            for (int i = 0; i < count; i++) {

                Venta v = generarVenta(i);
                String message = json.writeValueAsString(v);

                ProducerRecord<String, String> record =
                    new ProducerRecord<>(
                        topic,
                        v.customerId(),
                        message
                    );

                RecordMetadata metadata = producer
                    .send(record)
                    .get(30, TimeUnit.SECONDS);

                System.out.printf(
                    "VENTA_OK eventId=%s partition=%d offset=%d%n",
                    v.eventId(),
                    metadata.partition(),
                    metadata.offset()
                );

                System.out.println("EVENT_JSON=" + message);
            }

            producer.flush();
        }

        System.out.println("EVENTOS_ENVIADOS=" + count);
    }

    public static Venta generarVenta(int index) {

        return new Venta(
            UUID.randomUUID().toString(),
            Instant.now().toString(),
            "cliente-" + (index % 5 + 1),
            index % 2 == 0
                ? "TIENDA-CENTRO"
                : "TIENDA-NORTE",
            BigDecimal.valueOf(1000L + index * 150L),
            index % 3 + 1
        );
    }

    private static String requiredEnv(String name) {

        String value = System.getenv(name);

        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(
                "Variable requerida: " + name
            );
        }

        return value;
    }
}
