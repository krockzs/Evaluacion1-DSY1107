package cl.duoc.dsy1107.notificationservice.service;

import cl.duoc.dsy1107.notificationservice.dto.NotificationMessage;
import cl.duoc.dsy1107.notificationservice.entity.NotifyLog;
import cl.duoc.dsy1107.notificationservice.repository.NotifyLogRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import org.springframework.dao.TransientDataAccessException;
import org.springframework.dao.RecoverableDataAccessException;
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
            String payloadJson = mapper.writeValueAsString(message);
            // Reintentos locales acotados: sin requeue del broker ni ciclos infinitos.
            for (int attempt = 1; attempt <= 3; attempt++) {
                try {
                    NotifyLog notification = new NotifyLog();
                    notification.setOtId(message.otId());
                    notification.setClienteId(message.clienteId());
                    notification.setCanal(message.canal());
                    notification.setPayloadJson(payloadJson);
                    repo.saveAndFlush(notification);
                    channel.basicAck(deliveryTag, false);
                    log.info("Notification persisted and ACK sent; deliveryTag={}", deliveryTag);
                    return;
                } catch (TransientDataAccessException | RecoverableDataAccessException recoverable) {
                    if (attempt == 3) throw recoverable;
                    log.warn("Transient Oracle error, retry {}/3; deliveryTag={}", attempt + 1, deliveryTag, recoverable);
                    try {
                        Thread.sleep(100L * attempt);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                        throw new IllegalStateException("Notification retry interrupted", interrupted);
                    }
                }
            }
        } catch (JsonProcessingException | RuntimeException error) {
            log.error("Notification failed; deliveryTag={} -> DLQ (NACK, requeue=false)",
                    deliveryTag, error);
            channel.basicNack(deliveryTag, false, false);
        }
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
