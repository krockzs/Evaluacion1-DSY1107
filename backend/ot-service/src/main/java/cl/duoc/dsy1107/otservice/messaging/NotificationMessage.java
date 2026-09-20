package cl.duoc.dsy1107.otservice.messaging;

public record NotificationMessage(String type, String otId, String clienteId, String canal) {}
