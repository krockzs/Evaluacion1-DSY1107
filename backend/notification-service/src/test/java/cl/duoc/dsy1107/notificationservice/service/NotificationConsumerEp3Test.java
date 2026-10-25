package cl.duoc.dsy1107.notificationservice.service;

import cl.duoc.dsy1107.notificationservice.dto.NotificationMessage;
import cl.duoc.dsy1107.notificationservice.entity.NotifyLog;
import cl.duoc.dsy1107.notificationservice.repository.NotifyLogRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rabbitmq.client.Channel;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class NotificationConsumerEp3Test {
    private final NotifyLogRepository repo = mock(NotifyLogRepository.class);
    private final Channel channel = mock(Channel.class);
    private final NotificationConsumer consumer = new NotificationConsumer(repo, new ObjectMapper());

    @Test
    void successfulPersistenceAcknowledgesOnce() throws Exception {
        NotificationMessage message = new NotificationMessage("NotificarClienteOtCreada", "OT-1", "CLI-1", "email");
        consumer.consume(message, channel, 17L);
        verify(repo).saveAndFlush(any(NotifyLog.class));
        verify(channel).basicAck(17L, false);
        verify(channel, never()).basicNack(anyLong(), anyBoolean(), anyBoolean());
    }

    @Test
    void databaseFailureNacksWithoutRequeue() throws Exception {
        doThrow(new IllegalStateException("Oracle unavailable")).when(repo).saveAndFlush(any(NotifyLog.class));
        consumer.consume(new NotificationMessage("NotificarClienteOtCreada", "OT-1", "CLI-1", "email"), channel, 18L);
        verify(channel).basicNack(18L, false, false);
        verify(channel, never()).basicAck(anyLong(), anyBoolean());
    }

    @Test
    void invalidPayloadNacksWithoutPersisting() throws Exception {
        consumer.consume(new NotificationMessage("NotificarClienteOtCreada", "", "CLI-1", "email"), channel, 19L);
        verifyNoInteractions(repo);
        verify(channel).basicNack(19L, false, false);
        verify(channel, never()).basicAck(anyLong(), anyBoolean());
    }
}
