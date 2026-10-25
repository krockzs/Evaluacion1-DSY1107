package cl.duoc.dsy1107.rabbit_admin_service.service;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;
import cl.duoc.dsy1107.rabbit_admin_service.dto.AdminRequests.*;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.jupiter.api.Assertions.*;

/** Prueba requests HTTP reales frente a un servidor in-memory, sin RabbitMQ ni nube. */
class RabbitManagementHttpEp3Test {
    private HttpServer server;
    private RabbitAdminService admin;
    private final AtomicReference<String> path = new AtomicReference<>();
    private final AtomicReference<String> method = new AtomicReference<>();
    private final AtomicReference<String> body = new AtomicReference<>();
    private final AtomicReference<String> authorization = new AtomicReference<>();
    private volatile int responseStatus = 200;
    private volatile String responseJson = "{}";

    @BeforeEach void start() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", this::handle);
        server.start();
        RabbitManagementClient client = new RabbitManagementClient(new ObjectMapper(),
            "http://127.0.0.1:"+server.getAddress().getPort()+"/", "testuser", "testpass");
        admin = new RabbitAdminService(client,"/");
    }
    private void handle(HttpExchange exchange) throws IOException {
        try {
            path.set(exchange.getRequestURI().getRawPath());
            method.set(exchange.getRequestMethod());
            body.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            authorization.set(exchange.getRequestHeaders().getFirst("Authorization"));
            byte[] payload = responseJson.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            if ((responseStatus == 201 || responseStatus == 204) && responseJson.isEmpty()) {
                exchange.sendResponseHeaders(responseStatus, -1);
            } else {
                exchange.sendResponseHeaders(responseStatus, payload.length);
                exchange.getResponseBody().write(payload);
            }
        } finally { exchange.close(); }
    }
    @AfterEach void stop(){ if(server!=null) server.stop(0); }

    @Test void listarColasEnvíaGetAlManagement() {
        responseJson = "[{\"name\":\"ot.notifications.queue\",\"messages_ready\":2}]";
        Object result=admin.listQueues();
        assertEquals("GET",method.get());
        assertEquals("/api/queues/%2F",path.get());
        assertTrue(result instanceof java.util.List);
    }
    @Test void detalleUsaVhostCodificado() {
        admin.queue("ot.notifications.queue");
        assertEquals("GET",method.get());
        assertEquals("/api/queues/%2F/ot.notifications.queue", path.get());
    }
    @Test void crearColaRealizaPutConPayload() {
        admin.createQueue(new QueueRequest("ot.test.queue",true));
        assertEquals("PUT",method.get());
        assertEquals("/api/queues/%2F/ot.test.queue",path.get());
        assertTrue(body.get().contains("\"durable\":true"));
    }
    @Test void crearColaCon201SinCuerpoEsExito() {
        responseStatus=201;
        responseJson="";
        assertEquals(Map.of("status",201),admin.createQueue(new QueueRequest("ot.test.created",true)));
        assertEquals("PUT",method.get());
    }
    @Test void crearColaCon204SinCuerpoEsExito() {
        responseStatus=204;
        responseJson="";
        assertEquals(Map.of("status",204),admin.createQueue(new QueueRequest("ot.test.exists",true)));
    }
    @Test void publicarEnvíaJsonAlExchange() {
        admin.publish(new PublishRequest("ot.notifications.exchange","ot.created","{\"type\":\"demo\"}"));
        assertEquals("POST",method.get());
        assertEquals("/api/exchanges/%2F/ot.notifications.exchange/publish",path.get());
        assertTrue(body.get().contains("ack_requeue_true") == false);
        assertTrue(body.get().contains("payload_encoding"));
    }
    @Test void inspeccionSolicitaReencolado() {
        admin.peek("ot.notifications.queue",2);
        assertEquals("POST",method.get());
        assertEquals("/api/queues/%2F/ot.notifications.queue/get",path.get());
        assertTrue(body.get().contains("ack_requeue_true"));
        assertTrue(body.get().contains("\"count\":2"));
    }
    @Test void credencialesSoloViaBasicEnBackend() {
        admin.listExchanges();
        assertEquals("Basic "+Base64.getEncoder().encodeToString("testuser:testpass".getBytes(StandardCharsets.UTF_8)),authorization.get());
        assertFalse(body.get().contains("testpass"));
    }
    @Test void upstream404SePropagaComoErrorConEstado() {
        responseStatus=404;
        responseJson="{\"error\":\"not_found\"}";
        var ex=assertThrows(RabbitManagementClient.RabbitAdminUpstreamException.class,()->admin.queue("ot.missing"));
        assertEquals(404,ex.status);
    }
    @Test void bindingYEliminacionUsanRutasDelVhost() {
        admin.createBinding(new BindingRequest("ot.notifications.exchange","ot.notifications.queue","ot.created"));
        assertEquals("POST",method.get());
        assertEquals("/api/bindings/%2F/e/ot.notifications.exchange/q/ot.notifications.queue",path.get());
        assertTrue(body.get().contains("ot.created"));
        admin.deleteQueue("ot.test.queue");
        assertEquals("DELETE",method.get());
        assertEquals("/api/queues/%2F/ot.test.queue",path.get());
    }
}
