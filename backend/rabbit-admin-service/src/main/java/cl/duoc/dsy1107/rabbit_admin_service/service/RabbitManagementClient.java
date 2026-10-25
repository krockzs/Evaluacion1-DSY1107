package cl.duoc.dsy1107.rabbit_admin_service.service;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

/** API HTTP management de RabbitMQ: sin exponer credenciales al navegador. */
@Component
public class RabbitManagementClient {
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build();
    private final ObjectMapper json;
    private final URI base;
    private final String auth;
    public RabbitManagementClient(ObjectMapper json,
        @Value("${app.rabbit-admin.management-url}") String url,
        @Value("${app.rabbit-admin.username}") String user,
        @Value("${app.rabbit-admin.password}") String password) {
        this.json=json;
        this.base=URI.create(url.endsWith("/") ? url : url+"/");
        this.auth="Basic "+Base64.getEncoder().encodeToString((user+":"+password).getBytes(StandardCharsets.UTF_8));
    }
    public static String segment(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }
    public Object call(String method, String path, Object payload) {
        try {
            String body=payload == null ? "" : json.writeValueAsString(payload);
            HttpRequest req=HttpRequest.newBuilder(base.resolve(path))
                .timeout(Duration.ofSeconds(8))
                .header("Authorization",auth)
                .header("Content-Type","application/json")
                .method(method, body.isEmpty()?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(body))
                .build();
            HttpResponse<String> resp=http.send(req,HttpResponse.BodyHandlers.ofString());
            if(resp.statusCode()<200 || resp.statusCode()>=300)
                throw new RabbitAdminUpstreamException(resp.statusCode(), "RabbitMQ Management HTTP "+resp.statusCode());
            return resp.body().isBlank() ? java.util.Map.of("status", resp.statusCode()) : json.readValue(resp.body(), Object.class);
        } catch(RabbitAdminUpstreamException ex) { throw ex; }
          catch(Exception ex) { throw new RabbitAdminUpstreamException(502,"No fue posible contactar RabbitMQ Management",ex); }
    }
    public static final class RabbitAdminUpstreamException extends RuntimeException {
        public final int status;
        public RabbitAdminUpstreamException(int status,String message){super(message);this.status=status;}
        public RabbitAdminUpstreamException(int status,String message,Throwable cause){super(message,cause);this.status=status;}
    }
}
