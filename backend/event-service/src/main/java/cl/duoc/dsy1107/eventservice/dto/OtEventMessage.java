package cl.duoc.dsy1107.eventservice.dto;
import java.math.BigDecimal;
public record OtEventMessage(String eventType, String otId, String clienteId, BigDecimal total) {}
