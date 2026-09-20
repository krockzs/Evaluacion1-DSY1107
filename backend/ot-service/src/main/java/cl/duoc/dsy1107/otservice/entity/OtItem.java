package cl.duoc.dsy1107.otservice.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "OT_ITEM")
public class OtItem {
    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "ot_item_seq")
    @SequenceGenerator(name = "ot_item_seq", sequenceName = "SEQ_OT_ITEM", allocationSize = 1)
    @Column(name = "ITEM_ID")
    private Long itemId;

    @Column(name = "OT_ID", length = 24, nullable = false)
    private String otId;

    @Column(name = "CONCEPTO", length = 40, nullable = false)
    private String concepto;

    @Column(name = "CANTIDAD", precision = 10, scale = 2, nullable = false)
    private BigDecimal cantidad;

    @Column(name = "PRECIO_UNIT", precision = 12, scale = 0, nullable = false)
    private BigDecimal precioUnit;

    @Column(name = "SUBTOTAL", precision = 12, scale = 0, insertable = false, updatable = false)
    private BigDecimal subtotal;

    @Column(name = "CREATED_AT", insertable = false, updatable = false)
    private LocalDateTime createdAt;

    public Long getItemId() { return itemId; }
    public String getOtId() { return otId; }
    public void setOtId(String otId) { this.otId = otId; }
    public String getConcepto() { return concepto; }
    public void setConcepto(String concepto) { this.concepto = concepto; }
    public BigDecimal getCantidad() { return cantidad; }
    public void setCantidad(BigDecimal cantidad) { this.cantidad = cantidad; }
    public BigDecimal getPrecioUnit() { return precioUnit; }
    public void setPrecioUnit(BigDecimal precioUnit) { this.precioUnit = precioUnit; }
    public BigDecimal getSubtotal() { return subtotal; }
    public LocalDateTime getCreatedAt() { return createdAt; }
}
