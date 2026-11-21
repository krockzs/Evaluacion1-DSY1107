package cl.duoc.dsy1107.streams;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.utils.Bytes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.Grouped;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.Materialized;
import org.apache.kafka.streams.kstream.Produced;
import org.apache.kafka.streams.kstream.Repartitioned;
import org.apache.kafka.streams.kstream.TimeWindows;
import org.apache.kafka.streams.kstream.Windowed;
import org.apache.kafka.streams.processor.TimestampExtractor;
import org.apache.kafka.streams.processor.api.Processor;
import org.apache.kafka.streams.processor.api.ProcessorContext;
import org.apache.kafka.streams.processor.api.Record;
import org.apache.kafka.streams.state.KeyValueStore;
import org.apache.kafka.streams.state.Stores;
import org.apache.kafka.streams.state.WindowStore;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;

public final class VentasStreams {

    public static final String RAW = "ventas-raw";
    public static final String AGGREGATED = "ventas-agregadas";
    public static final String DLQ = "ventas-raw-dlq";
    private static final String SEEN_STORE = "ventas-eventid-dedup";
    private static final ObjectMapper JSON = new ObjectMapper();

    private VentasStreams() {}

    public record Check(
        boolean valid, String eventId, String store, long amountCents, String reason
    ) {}

    private static Check fail(String reason) {
        return new Check(false, null, null, 0, reason);
    }

    private static String requiredText(JsonNode root, String name) {
        JsonNode n = root.get(name);
        if (n == null || !n.isTextual() || n.asText().isBlank()) {
            throw new IllegalArgumentException("campo_obligatorio_" + name);
        }
        return n.asText().trim();
    }

    public static Check validate(String raw) {
        if (raw == null || raw.isBlank()) {
            return fail("payload_vacio");
        }

        try {
            JsonNode root = JSON.readTree(raw);
            if (root == null || !root.isObject()) {
                return fail("json_debe_ser_objeto");
            }

            String id = requiredText(root, "eventId");
            try {
                UUID.fromString(id);
            } catch (IllegalArgumentException e) {
                return fail("eventId_uuid_invalido");
            }

            String eventTime = requiredText(root, "eventTime");
            try {
                Instant.parse(eventTime);
            } catch (RuntimeException e) {
                return fail("eventTime_iso8601_invalido");
            }

            requiredText(root, "customerId");
            String store = requiredText(root, "store");

            JsonNode price = root.get("price");
            if (price == null || !price.isNumber()) {
                return fail("price_debe_ser_numero");
            }

            JsonNode quantity = root.get("quantity");
            if (quantity == null || !quantity.isIntegralNumber()
                    || !quantity.canConvertToInt() || quantity.asInt() <= 0) {
                return fail("quantity_entero_positivo_requerido");
            }

            long cents;
            try {
                cents = price.decimalValue().movePointRight(2).longValueExact();
                if (cents <= 0) {
                    return fail("price_debe_ser_positivo");
                }
                cents = Math.multiplyExact(cents, quantity.asInt());
            } catch (ArithmeticException e) {
                return fail("price_fuera_de_rango_o_precision");
            }

            return new Check(true, id, store, cents, null);
        } catch (JsonProcessingException e) {
            return fail("json_malformado");
        } catch (IllegalArgumentException e) {
            return fail(e.getMessage());
        }
    }

    public static String dlq(String originalKey, String originalValue, String reason) {
        ObjectNode node = JSON.createObjectNode();
        node.put("originalTopic", RAW);
        if (originalKey == null) {
            node.putNull("originalKey");
        } else {
            node.put("originalKey", originalKey);
        }
        if (originalValue == null) {
            node.putNull("originalValue");
        } else {
            node.put("originalValue", originalValue);
        }
        node.put("reason", reason);
        node.put("rejectedAt", Instant.now().toString());
        return node.toString();
    }

    public static String sumAggregate(String current, long amountCents) {
        String[] parts = current.split(":", -1);
        long count = Math.addExact(Long.parseLong(parts[0]), 1);
        long sum = Math.addExact(Long.parseLong(parts[1]), amountCents);
        return count + ":" + sum;
    }

    private static String aggregateJson(Windowed<String> window, String value) {
        String[] parts = value.split(":", -1);
        ObjectNode node = JSON.createObjectNode();
        node.put("store", window.key());
        node.put("windowStart", Instant.ofEpochMilli(window.window().start()).toString());
        node.put("windowEnd", Instant.ofEpochMilli(window.window().end()).toString());
        node.put("saleCount", Long.parseLong(parts[0]));
        node.put("totalAmount", BigDecimal.valueOf(Long.parseLong(parts[1]), 2));
        return node.toString();
    }

    public static Topology topology() {
        StreamsBuilder builder = new StreamsBuilder();

        builder.addStateStore(
            Stores.keyValueStoreBuilder(
                Stores.persistentKeyValueStore(SEEN_STORE),
                Serdes.String(),
                Serdes.Long()
            )
        );

        TimestampExtractor eventTimestamp = new TimestampExtractor() {
            @Override
            public long extract(ConsumerRecord<Object, Object> record, long previousTimestamp) {
                try {
                    JsonNode root = JSON.readTree((String) record.value());
                    return Instant.parse(root.path("eventTime").asText()).toEpochMilli();
                } catch (Exception ignored) {
                    return record.timestamp() >= 0
                        ? record.timestamp()
                        : Math.max(previousTimestamp, 0);
                }
            }
        };

        KStream<String, String> incoming = builder.stream(
            RAW,
            Consumed.with(Serdes.String(), Serdes.String())
                .withTimestampExtractor(eventTimestamp)
        );

        @SuppressWarnings("unchecked")
        KStream<String, String>[] routes = incoming.branch(
            (key, value) -> validate(value).valid(),
            (key, value) -> true
        );

        routes[1]
            .mapValues((key, value) -> dlq(key, value, validate(value).reason()))
            .to(DLQ, Produced.with(Serdes.String(), Serdes.String()));

        // Repartition by eventId: duplicate IDs reach the same state-store partition,
        // even if the original Kafka message keys differ.
        KStream<String, String> byEventId = routes[0]
            .selectKey((originalKey, value) -> validate(value).eventId())
            .repartition(
                Repartitioned.<String, String>as("ventas-by-eventid")
                    .withKeySerde(Serdes.String())
                    .withValueSerde(Serdes.String())
            );

        KStream<String, String> unique = byEventId.process(
            () -> new Processor<String, String, String, String>() {
                private ProcessorContext<String, String> context;
                private KeyValueStore<String, Long> seen;

                @Override
                public void init(ProcessorContext<String, String> ctx) {
                    context = ctx;
                    seen = ctx.getStateStore(SEEN_STORE);
                }

                @Override
                public void process(Record<String, String> record) {
                    if (seen.get(record.key()) != null) {
                        System.out.println("DUPLICATE_EVENT_ID=" + record.key());
                        return;
                    }
                    seen.put(record.key(), record.timestamp());
                    context.forward(record);
                }
            },
            SEEN_STORE
        );

        unique.selectKey((eventId, raw) -> validate(raw).store())
            .groupByKey(Grouped.with(Serdes.String(), Serdes.String()))
            .windowedBy(TimeWindows.ofSizeAndGrace(
                Duration.ofMinutes(1),
                Duration.ofSeconds(30)
            ))
            .aggregate(
                () -> "0:0",
                (store, raw, current) -> sumAggregate(
                    current,
                    validate(raw).amountCents()
                ),
                Materialized.<String, String, WindowStore<Bytes, byte[]>>as(
                    "ventas-ventanas-store"
                ).withKeySerde(Serdes.String())
                 .withValueSerde(Serdes.String())
            )
            .toStream()
            .map((window, total) -> KeyValue.pair(
                window.key(),
                aggregateJson(window, total)
            ))
            .to(AGGREGATED, Produced.with(Serdes.String(), Serdes.String()));

        return builder.build();
    }

    public static void main(String[] args) throws Exception {
        Properties config = new Properties();
        config.put(StreamsConfig.APPLICATION_ID_CONFIG, env(
            "KAFKA_APPLICATION_ID", "dsy1107-ventas-streams"
        ));
        config.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, env(
            "KAFKA_BOOTSTRAP_SERVERS",
            "172.31.91.91:9092,172.31.27.158:9092"
        ));
        config.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.EXACTLY_ONCE_V2);
        config.put(StreamsConfig.REPLICATION_FACTOR_CONFIG, 2);
        config.put(StreamsConfig.NUM_STREAM_THREADS_CONFIG, 1);
        config.put(StreamsConfig.COMMIT_INTERVAL_MS_CONFIG, 1000);
        config.put(StreamsConfig.CACHE_MAX_BYTES_BUFFERING_CONFIG, 0);
        config.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.StringSerde.class);
        config.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.StringSerde.class);
        config.put(StreamsConfig.STATE_DIR_CONFIG, env(
            "KAFKA_STATE_DIR", "/home/ubuntu/dsy1107-ep5/state"
        ));

        CountDownLatch done = new CountDownLatch(1);
        KafkaStreams streams = new KafkaStreams(topology(), config);

        streams.setStateListener(
            (newState, oldState) ->
                System.out.println("STREAMS_STATE=" + oldState + "->" + newState)
        );

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            streams.close(Duration.ofSeconds(15));
            done.countDown();
        }));

        streams.start();
        System.out.println("STREAMS_INICIADO=OK");
        done.await();
    }

    private static String env(String key, String fallback) {
        String value = System.getenv(key);
        return value == null || value.isBlank() ? fallback : value;
    }
}
