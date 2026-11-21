package cl.duoc.dsy1107.producer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class VentaTest {

    @Test
    void eventoDebeSerValidoYTipado() throws Exception {

        Venta v = VentasProducer.generarVenta(0);

        assertNotNull(UUID.fromString(v.eventId()));
        assertNotNull(Instant.parse(v.eventTime()));
        assertFalse(v.customerId().isBlank());
        assertFalse(v.store().isBlank());
        assertTrue(v.price().signum() > 0);
        assertTrue(v.quantity() > 0);

        ObjectMapper mapper = new ObjectMapper();

        JsonNode json = mapper.readTree(
            mapper.writeValueAsString(v)
        );

        assertTrue(json.hasNonNull("eventId"));
        assertTrue(json.hasNonNull("eventTime"));
        assertTrue(json.hasNonNull("customerId"));
        assertTrue(json.hasNonNull("store"));
        assertTrue(json.get("price").isNumber());
        assertTrue(json.get("quantity").isInt());
    }
}
