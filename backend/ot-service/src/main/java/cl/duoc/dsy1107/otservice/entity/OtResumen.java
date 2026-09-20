package cl.duoc.dsy1107.otservice.entity;

import jakarta.persistence.*;
import org.hibernate.annotations.Immutable;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Immutable
@Table(name = "V_OT_RESUMEN")
public class OtResumen {
    @Id
    @Column(name = "OT_ID")
    private String otId;
    @Column(name = "CLIENTE_ID")
    private String clienteId;
    @Column(name = "PATENTE")
    private String patente;
    @Column(name = "DESCRIPCION")
    private String descripcion;
    @Column(name = "TOTAL")
    private BigDecimal total;
    @Column(name = "CREATED_AT")
    private LocalDateTime createdAt;
    @Column(name = "N_ITEMS")
    private Long nItems;
    @Column(name = "SUBTOTAL_CALC")
    private BigDecimal subtotalCalc;

    public String getOtId() { return otId; }
    public String getClienteId() { return clienteId; }
    public String getPatente() { return patente; }
    public String getDescripcion() { return descripcion; }
    public BigDecimal getTotal() { return total; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public Long getNItems() { return nItems; }
    public BigDecimal getSubtotalCalc() { return subtotalCalc; }
}
