package cl.duoc.dsy1107.notificationservice.entity;
import jakarta.persistence.*; import java.time.LocalDateTime;
@Entity @Table(name="NOTIFY_LOG")
public class NotifyLog {
 @Id @GeneratedValue(strategy=GenerationType.SEQUENCE,generator="notify_seq") @SequenceGenerator(name="notify_seq",sequenceName="SEQ_NOTIFY_LOG",allocationSize=1) @Column(name="LOG_ID") private Long logId;
 @Column(name="OT_ID",length=24) private String otId; @Column(name="CLIENTE_ID",length=20) private String clienteId; @Column(name="CANAL",length=20) private String canal;
 @Lob @Column(name="PAYLOAD_JSON",nullable=false) private String payloadJson; @Column(name="CREATED_AT",insertable=false,updatable=false) private LocalDateTime createdAt;
 public Long getLogId(){return logId;} public String getOtId(){return otId;} public void setOtId(String v){otId=v;} public String getClienteId(){return clienteId;} public void setClienteId(String v){clienteId=v;} public String getCanal(){return canal;} public void setCanal(String v){canal=v;} public String getPayloadJson(){return payloadJson;} public void setPayloadJson(String v){payloadJson=v;} public LocalDateTime getCreatedAt(){return createdAt;}
}
