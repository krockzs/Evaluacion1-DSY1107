package cl.duoc.dsy1107.otservice.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record CreateOtItemRequest(
    @NotBlank @Size(max = 40) String concepto,
    @NotNull @Positive BigDecimal cantidad,
    @NotNull @PositiveOrZero BigDecimal precioUnit
) {}
