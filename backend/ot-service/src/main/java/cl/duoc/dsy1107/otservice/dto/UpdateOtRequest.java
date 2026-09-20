package cl.duoc.dsy1107.otservice.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record UpdateOtRequest(
    @Size(max = 20) String clienteId,
    @Size(max = 10) String patente,
    @Size(max = 200) String descripcion,
    @PositiveOrZero BigDecimal total
) {}
