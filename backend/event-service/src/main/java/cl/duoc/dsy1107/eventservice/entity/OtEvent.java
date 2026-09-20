package cl.duoc.dsy1107.eventservice.entity;
import jakarta.persistence.*;
import java.time.LocalDateTime;
@Entity @Table(name="OT_EVENT")
public class OtEvent {
    @Id @GeneratedValue(strategy=GenerationType.SEQUENCE,generator="event_seq")
    @SequenceGenerator(name="event_seq",sequenceName="SEQ_EVENT_LOG",allocationSize=1)
    @Column(name="EVENT_ID") private Long eventId;
    @Column(name="OT_ID",length=24) private String otId;
    @Column(name="EVENT_TYPE",length=40,nullable=false) private String eventType;
    @Lob @Column(name="PAYLOAD_JSON",nullable=false) private String payloadJson;
    @Column(name="CREATED_AT",insertable=false,updatable=false) private LocalDateTime createdAt;
    public Long getEventId(){return eventId;} public String getOtId(){return otId;} public void setOtId(String v){otId=v;}
    public String getEventType(){return eventType;} public void setEventType(String v){eventType=v;}
    public String getPayloadJson(){return payloadJson;} public void setPayloadJson(String v){payloadJson=v;} public LocalDateTime getCreatedAt(){return createdAt;}
}
