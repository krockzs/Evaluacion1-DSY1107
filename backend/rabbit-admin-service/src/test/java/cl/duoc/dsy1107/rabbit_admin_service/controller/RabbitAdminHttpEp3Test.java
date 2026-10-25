package cl.duoc.dsy1107.rabbit_admin_service.controller;

import cl.duoc.dsy1107.rabbit_admin_service.service.RabbitAdminService;
import cl.duoc.dsy1107.rabbit_admin_service.exception.AdminErrorHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class RabbitAdminHttpEp3Test {
    private RabbitAdminService service;
    private MockMvc mvc;

    @BeforeEach
    void setup() {
        service = mock(RabbitAdminService.class);
        mvc = MockMvcBuilders.standaloneSetup(new RabbitAdminController(service))
            .setControllerAdvice(new AdminErrorHandler())
            .build();
    }

    @Test void getQueues() throws Exception {
        when(service.listQueues()).thenReturn(List.of(Map.of("name", "ot.notifications.queue")));
        mvc.perform(get("/api/admin/queues")).andExpect(status().isOk())
            .andExpect(jsonPath("$[0].name").value("ot.notifications.queue"));
        verify(service).listQueues();
    }

    @Test void getQueueDetails() throws Exception {
        when(service.queue("cola.prueba")).thenReturn(Map.of("messages_ready", 2));
        mvc.perform(get("/api/admin/queues/cola.prueba")).andExpect(status().isOk())
            .andExpect(jsonPath("$.messages_ready").value(2));
    }

    @Test void getExchanges() throws Exception {
        when(service.listExchanges()).thenReturn(List.of(Map.of("name", "demo.exchange")));
        mvc.perform(get("/api/admin/exchanges")).andExpect(status().isOk());
    }

    @Test void getBindings() throws Exception {
        when(service.listBindings()).thenReturn(List.of());
        mvc.perform(get("/api/admin/bindings")).andExpect(status().isOk());
    }

    @Test void postQueue() throws Exception {
        when(service.createQueue(any())).thenReturn(Map.of("status", 201));
        mvc.perform(post("/api/admin/queues").contentType(MediaType.APPLICATION_JSON)
            .content("{\"name\":\"cola.prueba\",\"durable\":true}"))
            .andExpect(status().isOk());
        verify(service).createQueue(any());
    }

    @Test void postQueueBlankNameRejected() throws Exception {
        mvc.perform(post("/api/admin/queues").contentType(MediaType.APPLICATION_JSON)
            .content("{\"name\":\"\",\"durable\":true}"))
            .andExpect(status().isBadRequest());
        verifyNoInteractions(service);
    }

    @Test void postExchangeInvalidTypeRejected() throws Exception {
        mvc.perform(post("/api/admin/exchanges").contentType(MediaType.APPLICATION_JSON)
            .content("{\"name\":\"prueba\",\"type\":\"incorrecto\",\"durable\":true}"))
            .andExpect(status().isBadRequest());
        verifyNoInteractions(service);
    }

    @Test void postPublish() throws Exception {
        when(service.publish(any())).thenReturn(Map.of("routed", true));
        mvc.perform(post("/api/admin/publish").contentType(MediaType.APPLICATION_JSON)
            .content("{\"exchange\":\"demo\",\"routingKey\":\"demo.key\",\"payload\":\"{}\"}"))
            .andExpect(status().isOk()).andExpect(jsonPath("$.routed").value(true));
    }

    @Test void deleteQueue() throws Exception {
        when(service.deleteQueue("cola.prueba")).thenReturn(Map.of("status", 204));
        mvc.perform(delete("/api/admin/queues/cola.prueba")).andExpect(status().isOk());
        verify(service).deleteQueue("cola.prueba");
    }

    @Test void peekEndpoint() throws Exception {
        when(service.peek("cola.prueba", 2)).thenReturn(List.of());
        mvc.perform(get("/api/admin/queues/cola.prueba/messages?count=2"))
            .andExpect(status().isOk());
        verify(service).peek("cola.prueba", 2);
    }

    @Test void queueManagementNotFound() throws Exception {
        when(service.queue("ausente")).thenThrow(new
            cl.duoc.dsy1107.rabbit_admin_service.service.RabbitManagementClient.RabbitAdminUpstreamException(404,"RabbitMQ Management HTTP 404"));
        mvc.perform(get("/api/admin/queues/ausente")).andExpect(status().isNotFound());
    }
}
