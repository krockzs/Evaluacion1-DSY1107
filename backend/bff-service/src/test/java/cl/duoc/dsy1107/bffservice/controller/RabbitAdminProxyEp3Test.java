package cl.duoc.dsy1107.bffservice.controller;

import com.sun.net.httpserver.HttpServer;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.client.RestClient;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

class RabbitAdminProxyEp3Test {
    private HttpServer server;
    private RabbitAdminProxyController controller;
    private final AtomicReference<String> lastPath = new AtomicReference<>();
    private final AtomicReference<String> lastMethod = new AtomicReference<>();
    private final AtomicReference<String> lastAuth = new AtomicReference<>();
    private final AtomicReference<String> lastBody = new AtomicReference<>();

    @BeforeEach void setup() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            lastPath.set(exchange.getRequestURI().toString());
            lastMethod.set(exchange.getRequestMethod());
            lastAuth.set(exchange.getRequestHeaders().getFirst("Authorization"));
            lastBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            byte[] payload = "{\"ok\":true}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, payload.length);
            try (var out = exchange.getResponseBody()) { out.write(payload); }
        });
        server.start();
        controller = new RabbitAdminProxyController(RestClient.builder(),
                "http://127.0.0.1:" + server.getAddress().getPort());
    }

    @AfterEach void stop() { if (server != null) server.stop(0); }

    private static Jwt jwt() {
        return Jwt.withTokenValue("ep3-test-token").header("alg", "none")
                .claim("sub", "test-admin").build();
    }
    private static HttpServletRequest request(String method, String path, String query) {
        var r = new MockHttpServletRequest(method, path);
        if (query != null) r.setQueryString(query);
        return r;
    }

    @Test void getQueuesForwardsJwt() {
        ResponseEntity<String> result = controller.forward(request("GET", "/api/admin/queues", null), jwt(), null);
        assertEquals(200, result.getStatusCode().value());
        assertEquals("/api/admin/queues", lastPath.get());
        assertEquals("GET", lastMethod.get());
        assertEquals("Bearer ep3-test-token", lastAuth.get());
        assertEquals("{\"ok\":true}", result.getBody());
    }

    @Test void inspectionPreservesCountQuery() {
        controller.forward(request("GET", "/api/admin/queues/ot.notifications.dlq/messages", "count=10"), jwt(), null);
        assertEquals("/api/admin/queues/ot.notifications.dlq/messages?count=10", lastPath.get());
    }

    @Test void publishPreservesJsonPayload() {
        var request = new MockHttpServletRequest("POST", "/api/admin/publish");
        request.setContentType("application/json");
        String body = "{\"exchange\":\"ot.notifications.exchange\",\"payload\":\"test\"}";
        controller.forward(request, jwt(), body);
        assertEquals("POST", lastMethod.get());
        assertEquals(body, lastBody.get());
        assertEquals("Bearer ep3-test-token", lastAuth.get());
    }

    @Test void deleteUsesExpectedMethodAndRoute() {
        controller.forward(request("DELETE", "/api/admin/queues/ot.test", null), jwt(), null);
        assertEquals("DELETE", lastMethod.get());
        assertEquals("/api/admin/queues/ot.test", lastPath.get());
    }

    @Test void rejectsMissingJwt() {
        ResponseEntity<String> response = controller.forward(request("GET", "/api/admin/queues", null), null, null);
        assertEquals(401, response.getStatusCode().value());
        assertNull(lastPath.get());
    }

    @Test void rejectsUnrelatedPath() {
        ResponseEntity<String> response = controller.forward(request("GET", "/api/ots", null), jwt(), null);
        assertEquals(404, response.getStatusCode().value());
        assertNull(lastPath.get());
    }
}
