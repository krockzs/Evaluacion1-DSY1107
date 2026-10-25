package cl.duoc.dsy1107.rabbit_admin_service.exception;

import cl.duoc.dsy1107.rabbit_admin_service.service.RabbitManagementClient.RabbitAdminUpstreamException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class AdminErrorHandler {
    @ExceptionHandler({IllegalArgumentException.class,MethodArgumentNotValidException.class})
    public ResponseEntity<?> invalid(Exception ex){return ResponseEntity.badRequest().body(Map.of("error","Entrada inválida"));}
    @ExceptionHandler(RabbitAdminUpstreamException.class)
    public ResponseEntity<?> broker(RabbitAdminUpstreamException ex){
        HttpStatus status = ex.status==404?HttpStatus.NOT_FOUND:ex.status==409?HttpStatus.CONFLICT:HttpStatus.BAD_GATEWAY;
        return ResponseEntity.status(status).body(Map.of("error",ex.getMessage()));
    }
}
