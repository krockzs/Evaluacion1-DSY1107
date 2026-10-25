package cl.duoc.dsy1107.notificationservice.service;

import cl.duoc.dsy1107.notificationservice.dto.NotificationMessage;
import cl.duoc.dsy1107.notificationservice.entity.NotifyLog;
import cl.duoc.dsy1107.notificationservice.repository.NotifyLogRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.support.AmqpHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Service;

/** Procesa notificaciones; confirma solamente después de persistirlas. */
@Service
public class NotificationConsumer {
    private static final Logger log = LoggerFactory.getLogger(NotificationConsumer.class);
    private final NotifyLogRepository repo;
    private final ObjectMapper mapper;

    public NotificationConsumer(NotifyLogRepository repo, ObjectMapper mapper) {
        this.repo = repo;
        this.mapper = mapper;
    }

    @RabbitListener(queues = "${app.rabbitmq.queue}")
    public void consume(NotificationMessage message, Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag) throws IOException {
        try {
            validate(message);
            NotifyLog notification = new NotifyLog();
            notification.setOtId(message.otId());
            notification.setClienteId(message.clienteId());
            notification.setCanal(message.canal());
            notification.setPayloadJson(mapper.writeValueAsString(message));
            // saveAndFlush termina la transacción del repositorio antes de confirmar el broker.
            repo.saveAndFlush(notification);
        } catch (JsonProcessingException | RuntimeException error) {
            log.error("Notification failed; deliveryTag={} -> DLQ (NACK, requeue=false)",
                    deliveryTag, error);
            channel.basicNack(deliveryTag, false, false);
            return;
        }
        // Si la confirmación falla, la excepción se propaga: no reenviar otro NACK.
        channel.basicAck(deliveryTag, false);
        log.info("Notification persisted and ACK sent; deliveryTag={}", deliveryTag);
    }

    private static void validate(NotificationMessage message) {
        if (message == null || isBlank(message.type()) || isBlank(message.otId())
                || isBlank(message.clienteId()) || isBlank(message.canal())) {
            throw new IllegalArgumentException("Invalid notification payload");
        }
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }
}
