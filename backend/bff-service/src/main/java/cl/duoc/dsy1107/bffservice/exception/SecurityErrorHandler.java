package cl.duoc.dsy1107.bffservice.exception;
import org.springframework.http.*; import org.springframework.security.access.AccessDeniedException; import org.springframework.web.bind.annotation.*; import org.springframework.web.client.RestClientResponseException; import java.time.Instant; import java.util.Map;
@RestControllerAdvice public class SecurityErrorHandler {
 @ExceptionHandler(AccessDeniedException.class) ResponseEntity<Map<String,Object>> denied(AccessDeniedException ex){return ResponseEntity.status(403).body(Map.of("timestamp",Instant.now().toString(),"status",403,"error","Forbidden","message","Token válido, pero sin rol/scope suficiente"));}
 @ExceptionHandler(RestClientResponseException.class) ResponseEntity<String> backend(RestClientResponseException ex){return ResponseEntity.status(ex.getStatusCode()).contentType(MediaType.APPLICATION_JSON).body(ex.getResponseBodyAsString());}
}
