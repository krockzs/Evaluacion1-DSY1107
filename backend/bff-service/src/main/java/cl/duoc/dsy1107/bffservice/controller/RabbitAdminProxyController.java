package cl.duoc.dsy1107.bffservice.controller;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.net.URI;

/** Proxy del panel Rabbit Admin. El BFF valida issuer/audience para cualquier usuario autenticado.
 * Rabbit Admin validará nuevamente el JWT antes de permitir operaciones reales.
 */
@RestController
public class RabbitAdminProxyController {
    private final RestClient client;
    private final URI adminBase;

    public RabbitAdminProxyController(RestClient.Builder builder,
            @Value("${app.services.rabbit-admin}") String adminUrl) {
        this.adminBase = URI.create(adminUrl);
        if (!"http".equalsIgnoreCase(adminBase.getScheme()) && !"https".equalsIgnoreCase(adminBase.getScheme())) {
            throw new IllegalArgumentException("rabbit-admin URL debe usar HTTP(S)");
        }
        this.client = builder.build();
    }

    @RequestMapping(path = {"/api/admin", "/api/admin/**"})
    public ResponseEntity<String> forward(HttpServletRequest request,
            @AuthenticationPrincipal Jwt jwt,
            @RequestBody(required = false) String body) {
        if (jwt == null) return ResponseEntity.status(401).build();
        String path = request.getRequestURI();
        if (!path.startsWith("/api/admin")) return ResponseEntity.notFound().build();
        String suffix = path.substring("/api/admin".length());
        String query = request.getQueryString();
        String relative = "/api/admin" + suffix + (query == null ? "" : "?" + query);
        URI target = URI.create(adminBase.toString().replaceAll("/+$", "") + relative);
        RestClient.RequestBodySpec outgoing = client.method(org.springframework.http.HttpMethod.valueOf(request.getMethod()))
                .uri(target)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + jwt.getTokenValue());
        String contentType = request.getContentType();
        if (contentType != null) outgoing.contentType(MediaType.parseMediaType(contentType));
        if (body != null && !body.isBlank()) outgoing.body(body);
        return outgoing.exchange((req, resp) -> {
            HttpStatusCode status = resp.getStatusCode();
            String responseBody = new String(resp.getBody().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
            ResponseEntity.BodyBuilder result = ResponseEntity.status(status);
            MediaType responseType = resp.getHeaders().getContentType();
            if (responseType != null) result.contentType(responseType);
            return result.body(responseBody);
        });
    }
}
