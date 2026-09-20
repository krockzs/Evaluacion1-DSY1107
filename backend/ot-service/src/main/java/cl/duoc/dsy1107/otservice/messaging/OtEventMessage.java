package cl.duoc.dsy1107.otservice.messaging;

import java.math.BigDecimal;

public record OtEventMessage(String eventType, String otId, String clienteId, BigDecimal total) {}
