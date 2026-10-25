package cl.duoc.dsy1107.rabbit_admin_service.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Max;

public final class AdminRequests {
    private AdminRequests() {}
    public record QueueRequest(@NotBlank @Size(max=120) String name, boolean durable) {}
    public record ExchangeRequest(@NotBlank @Size(max=120) String name,
        @NotBlank @Pattern(regexp="direct|topic|fanout|headers") String type, boolean durable) {}
    public record BindingRequest(@NotBlank String source, @NotBlank String destination,
        @NotBlank String routingKey) {}
    public record PublishRequest(@NotBlank String exchange, String routingKey,
        @NotBlank String payload) {}
    public record PeekRequest(@Min(1) @Max(10) int count) {}
}
