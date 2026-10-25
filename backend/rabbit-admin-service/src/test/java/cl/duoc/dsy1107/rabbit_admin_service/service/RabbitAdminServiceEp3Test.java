package cl.duoc.dsy1107.rabbit_admin_service.service;

import cl.duoc.dsy1107.rabbit_admin_service.dto.AdminRequests.*;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
import java.util.Map;

class RabbitAdminServiceEp3Test {
    private final RabbitManagementClient client = mock(RabbitManagementClient.class);
    private final RabbitAdminService service = new RabbitAdminService(client, "/");

    @Test void listQueues() {
        service.listQueues();
        verify(client).call("GET", "api/queues/%2F", null);
    }
    @Test void getQueue() {
        service.queue("cola.test");
        verify(client).call("GET", "api/queues/%2F/cola.test", null);
    }
    @Test void createQueue() {
        when(client.call("GET","api/queues/%2F/cola.prueba",null)).thenThrow(new RabbitManagementClient.RabbitAdminUpstreamException(404,"not found"));
        service.createQueue(new QueueRequest("cola.prueba", true));
        verify(client).call("PUT", "api/queues/%2F/cola.prueba",
          Map.of("durable", true, "auto_delete", false, "arguments", Map.of()));
    }
    @Test void existingQueueIsNotRedeclared() {
        when(client.call("GET","api/queues/%2F/ot.notifications.queue",null)).thenReturn(Map.of("name","ot.notifications.queue"));
        Object result=service.createQueue(new QueueRequest("ot.notifications.queue",true));
        assertEquals(false,((Map<?,?>)result).get("created"));
        verify(client,never()).call(eq("PUT"),anyString(),any());
    }
    @Test void deleteQueue() {
        service.deleteQueue("cola.prueba");
        verify(client).call("DELETE", "api/queues/%2F/cola.prueba", null);
    }
    @Test void inspectWithRequeue() {
        service.peek("cola.prueba", 2);
        verify(client).call("POST", "api/queues/%2F/cola.prueba/get",
          Map.of("count",2,"ackmode","ack_requeue_true","encoding","auto","truncate",8192));
    }
    @Test void rejectsInvalidInspectionCount() {
        assertThrows(IllegalArgumentException.class, () -> service.peek("cola.prueba", 11));
        verifyNoInteractions(client);
    }
    @Test void listExchanges() {
        service.listExchanges();
        verify(client).call("GET", "api/exchanges/%2F", null);
    }
    @Test void createExchange() {
        when(client.call("GET", "api/exchanges/%2F/test.ex", null)).thenThrow(new RabbitManagementClient.RabbitAdminUpstreamException(404,"not found"));
        service.createExchange(new ExchangeRequest("test.ex", "direct", true));
        verify(client).call("PUT", "api/exchanges/%2F/test.ex",
          Map.of("type","direct","durable",true,"auto_delete",false,"internal",false,"arguments",Map.of()));
    }
    @Test void existingExchangeIsNotRedeclared() {
        when(client.call("GET", "api/exchanges/%2F/ot.notifications.exchange", null))
            .thenReturn(Map.of("name","ot.notifications.exchange","type","direct"));
        Object result=service.createExchange(new ExchangeRequest("ot.notifications.exchange","direct",true));
        assertEquals(false,((Map<?,?>)result).get("created"));
        verify(client,never()).call(eq("PUT"),anyString(),any());
    }
    @Test void deleteExchange() {
        service.deleteExchange("test.ex");
        verify(client).call("DELETE", "api/exchanges/%2F/test.ex", null);
    }
    @Test void listBindings() {
        service.listBindings();
        verify(client).call("GET", "api/bindings/%2F", null);
    }
    @Test void createBinding() {
        service.createBinding(new BindingRequest("test.ex", "cola.prueba", "rk"));
        verify(client).call("POST", "api/bindings/%2F/e/test.ex/q/cola.prueba",
          Map.of("routing_key","rk","arguments",Map.of()));
    }
    @Test void deleteBinding() {
        service.deleteBinding("test.ex", "cola.prueba", "rk");
        verify(client).call("DELETE", "api/bindings/%2F/e/test.ex/q/cola.prueba/rk", null);
    }
    @Test void publishTestMessage() {
        service.publish(new PublishRequest("test.ex", "rk", "{\"type\":\"test\"}"));
        verify(client).call("POST", "api/exchanges/%2F/test.ex/publish",
          Map.of("properties",Map.of("content_type","application/json"),"routing_key","rk",
          "payload","{\"type\":\"test\"}","payload_encoding","string"));
    }
    @Test void rejectReservedQueueName() {
        assertThrows(IllegalArgumentException.class, () -> service.createQueue(new QueueRequest("amq.reserved",true)));
        verifyNoInteractions(client);
    }
    @Test void rejectExcessivePayload() {
        assertThrows(IllegalArgumentException.class, () -> service.publish(new PublishRequest("test.ex","rk","x".repeat(16385))));
        verifyNoInteractions(client);
    }
}
