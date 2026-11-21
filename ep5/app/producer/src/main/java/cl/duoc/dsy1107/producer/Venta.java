package cl.duoc.dsy1107.producer;

import java.math.BigDecimal;

public record Venta(
    String eventId,
    String eventTime,
    String customerId,
    String store,
    BigDecimal price,
    int quantity
) {}
