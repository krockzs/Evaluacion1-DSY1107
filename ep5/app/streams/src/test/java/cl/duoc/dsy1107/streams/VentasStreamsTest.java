package cl.duoc.dsy1107.streams;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.TopologyTestDriver;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;
import java.time.Instant;
import java.util.Properties;

import static org.junit.jupiter.api.Assertions.*;

class VentasStreamsTest {

    @TempDir
    Path stateDir;

    private static final ObjectMapper JSON = new ObjectMapper();

    private static String sale(String id, String time, int quantity) {
        return String.format(
            "{\"eventId\":\"%s\",\"eventTime\":\"%s\",\"customerId\":\"cliente-7\","
                + "\"store\":\"TIENDA-CENTRO\",\"price\":1000,\"quantity\":%d}",
            id, time, quantity
        );
    }

    @Test
    void validaContratoYDetectaErrores() {
        String id = "11111111-1111-4111-8111-111111111111";
        assertTrue(VentasStreams.validate(sale(id, "2026-11-21T20:11:39Z", 2)).valid());
        assertEquals(200000, VentasStreams.validate(
            sale(id, "2026-11-21T20:11:39Z", 2)
        ).amountCents());

        assertEquals("json_malformado", VentasStreams.validate("{bad").reason());
        assertEquals("quantity_entero_positivo_requerido", VentasStreams.validate(
            sale(id, "2026-11-21T20:11:39Z", 0)
        ).reason());

        assertEquals("price_debe_ser_positivo", VentasStreams.validate(
            sale(id, "2026-11-21T20:11:39Z", 2).replace("1000", "-5")
        ).reason());
    }

    @Test
    void dlqPreservaDatosOriginalesYMotivo() throws Exception {
        String raw = "{malformado";
        JsonNode error = JSON.readTree(VentasStreams.dlq(
            "clave-original", raw, "json_malformado"
        ));
        assertEquals("ventas-raw", error.get("originalTopic").asText());
        assertEquals("clave-original", error.get("originalKey").asText());
        assertEquals(raw, error.get("originalValue").asText());
        assertEquals("json_malformado", error.get("reason").asText());
    }

    @Test
    void topologiaValidaDeduplicaAgregaYDerivaDlq() throws Exception {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "ventas-streams-test");
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "dummy:9092");
        props.put(StreamsConfig.STATE_DIR_CONFIG, stateDir.toString());
        props.put(StreamsConfig.CACHE_MAX_BYTES_BUFFERING_CONFIG, 0);
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.StringSerde.class);
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.StringSerde.class);

        try (TopologyTestDriver driver = new TopologyTestDriver(VentasStreams.topology(), props)) {
            TestInputTopic<String, String> raw = driver.createInputTopic(
                VentasStreams.RAW,
                Serdes.String().serializer(),
                Serdes.String().serializer()
            );

            TestOutputTopic<String, String> aggregated = driver.createOutputTopic(
                VentasStreams.AGGREGATED,
                Serdes.String().deserializer(),
                Serdes.String().deserializer()
            );

            TestOutputTopic<String, String> dlq = driver.createOutputTopic(
                VentasStreams.DLQ,
                Serdes.String().deserializer(),
                Serdes.String().deserializer()
            );

            String id = "11111111-1111-4111-8111-111111111111";
            String time = "2026-11-21T20:11:39Z";
            String valid = sale(id, time, 2);

            raw.pipeInput("cliente-7", valid, Instant.parse(time));

            assertFalse(aggregated.isEmpty());
            JsonNode first = JSON.readTree(aggregated.readValue());
            assertEquals("TIENDA-CENTRO", first.get("store").asText());
            assertEquals(1, first.get("saleCount").asInt());
            assertEquals(2000, first.get("totalAmount").asInt());

            // Mismo eventId con distinta clave original: no se contabiliza dos veces.
            raw.pipeInput("clave-distinta", valid, Instant.parse(time));
            assertTrue(aggregated.isEmpty());

            raw.pipeInput("clave-malformada", "{bad", Instant.parse(time));
            assertTrue(aggregated.isEmpty());
            assertFalse(dlq.isEmpty());

            JsonNode rejected = JSON.readTree(dlq.readValue());
            assertEquals("clave-malformada", rejected.get("originalKey").asText());
            assertEquals("{bad", rejected.get("originalValue").asText());
            assertEquals("json_malformado", rejected.get("reason").asText());

            String second = sale(
                "22222222-2222-4222-8222-222222222222", time, 1
            );
            raw.pipeInput("cliente-7", second, Instant.parse(time));

            assertFalse(aggregated.isEmpty());
            JsonNode updated = JSON.readTree(aggregated.readValue());
            assertEquals(2, updated.get("saleCount").asInt());
            assertEquals(3000, updated.get("totalAmount").asInt());
        }
    }

    @Test
    void aceptaTardioDentroDeGraciaYDescartaFueraDeGracia() throws Exception {
        Properties props = new Properties();
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, "ventas-streams-late-test");
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "dummy:9092");
        props.put(StreamsConfig.STATE_DIR_CONFIG, stateDir.toString());
        props.put(StreamsConfig.CACHE_MAX_BYTES_BUFFERING_CONFIG, 0);
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.StringSerde.class);
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.StringSerde.class);

        try (TopologyTestDriver driver = new TopologyTestDriver(VentasStreams.topology(), props)) {
            TestInputTopic<String, String> raw = driver.createInputTopic(
                VentasStreams.RAW,
                Serdes.String().serializer(),
                Serdes.String().serializer()
            );
            TestOutputTopic<String, String> aggregated = driver.createOutputTopic(
                VentasStreams.AGGREGATED,
                Serdes.String().deserializer(),
                Serdes.String().deserializer()
            );
            TestOutputTopic<String, String> dlq = driver.createOutputTopic(
                VentasStreams.DLQ,
                Serdes.String().deserializer(),
                Serdes.String().deserializer()
            );

            // La primera venta crea la ventana [20:00:00, 20:01:00).
            String t0 = "2026-11-21T20:00:10Z";
            raw.pipeInput(
                "primero",
                sale("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", t0, 1),
                Instant.parse(t0)
            );
            JsonNode first = JSON.readTree(aggregated.readValue());
            assertEquals("2026-11-21T20:00:00Z", first.get("windowStart").asText());
            assertEquals(1, first.get("saleCount").asInt());
            assertEquals(1000, first.get("totalAmount").asInt());

            // Avanza stream-time a 20:01:20. La ventana anterior sigue
            // abierta gracias a los 30 segundos de tolerancia.
            String advanceWithinGrace = "2026-11-21T20:01:20Z";
            raw.pipeInput(
                "avance-gracia",
                sale("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", advanceWithinGrace, 1),
                Instant.parse(advanceWithinGrace)
            );
            assertEquals("2026-11-21T20:01:00Z",
                JSON.readTree(aggregated.readValue()).get("windowStart").asText());

            // Llega despues, pero su timestamp pertenece a la primera ventana.
            String lateButAccepted = "2026-11-21T20:00:15Z";
            raw.pipeInput(
                "tardio-dentro-gracia",
                sale("cccccccc-cccc-4ccc-8ccc-cccccccccccc", lateButAccepted, 1),
                Instant.parse(lateButAccepted)
            );
            JsonNode accepted = JSON.readTree(aggregated.readValue());
            assertEquals("2026-11-21T20:00:00Z", accepted.get("windowStart").asText());
            assertEquals(2, accepted.get("saleCount").asInt());
            assertEquals(2000, accepted.get("totalAmount").asInt());
            assertTrue(aggregated.isEmpty());

            // Avanza stream-time mas alla del cierre 20:01:30.
            String advancePastGrace = "2026-11-21T20:02:30Z";
            raw.pipeInput(
                "avance-cierre",
                sale("dddddddd-dddd-4ddd-8ddd-dddddddddddd", advancePastGrace, 1),
                Instant.parse(advancePastGrace)
            );
            assertEquals("2026-11-21T20:02:00Z",
                JSON.readTree(aggregated.readValue()).get("windowStart").asText());

            // Es un evento valido, pero demasiado tardio para 20:00.
            String tooLate = "2026-11-21T20:00:25Z";
            raw.pipeInput(
                "tardio-fuera-gracia",
                sale("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", tooLate, 1),
                Instant.parse(tooLate)
            );
            assertTrue(aggregated.isEmpty(),
                "Un evento fuera de gracia no debe alterar agregaciones");
            assertTrue(dlq.isEmpty(),
                "La politica actual descarta tardios, no los envia a DLQ");

            System.out.println("EVENTO_TARDIO_DENTRO_GRACIA=OK");
            System.out.println("EVENTO_TARDIO_FUERA_GRACIA_DESCARTADO=OK");
            System.out.println("VENTANA_1_MIN_GRACIA_30_SEG=OK");
        }
    }

}
