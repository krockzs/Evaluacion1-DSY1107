package cl.duoc.dsy1107.otservice.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "OT")
public class Ot {
    @Id
    @Column(name = "OT_ID", length = 24, nullable = false)
    private String otId;

    @Column(name = "CLIENTE_ID", length = 20, nullable = false)
    private String clienteId;

    @Column(name = "PATENTE", length = 10, nullable = false)
    private String patente;

    @Column(name = "DESCRIPCION", length = 200)
    private String descripcion;

    @Column(name = "TOTAL", precision = 12, scale = 0, nullable = false)
    private BigDecimal total = BigDecimal.ZERO;

    @Column(name = "CREATED_AT", insertable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "UPDATED_AT", insertable = false, updatable = false)
    private LocalDateTime updatedAt;

    public String getOtId() { return otId; }
    public void setOtId(String otId) { this.otId = otId; }
    public String getClienteId() { return clienteId; }
    public void setClienteId(String clienteId) { this.clienteId = clienteId; }
    public String getPatente() { return patente; }
    public void setPatente(String patente) { this.patente = patente; }
    public String getDescripcion() { return descripcion; }
    public void setDescripcion(String descripcion) { this.descripcion = descripcion; }
    public BigDecimal getTotal() { return total; }
    public void setTotal(BigDecimal total) { this.total = total; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }
}
