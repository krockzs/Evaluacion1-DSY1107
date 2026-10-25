package cl.duoc.dsy1107.notificationservice.dto;

import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import java.nio.charset.StandardCharsets;
import static org.junit.jupiter.api.Assertions.*;

class JsonContractEp3Test {
    @Test
    void productorYConsumidorMantienenContratoJson() {
        JacksonJsonMessageConverter converter = new JacksonJsonMessageConverter();
        NotificationMessage original = new NotificationMessage("NotificarClienteOtCreada", "OT-2026-000001", "cliente-001", "email");
        Message message = converter.toMessage(original, new org.springframework.amqp.core.MessageProperties());
        String json = new String(message.getBody(), StandardCharsets.UTF_8);
        assertTrue(json.contains("\"type\""), json);
        assertTrue(json.contains("\"otId\""), json);
        assertTrue(json.contains("\"clienteId\""), json);
        assertTrue(json.contains("\"canal\""), json);
        message.getMessageProperties().setInferredArgumentType(NotificationMessage.class);
        Object restored = converter.fromMessage(message);
        assertInstanceOf(NotificationMessage.class, restored);
        assertEquals(original, restored);
    }
}
