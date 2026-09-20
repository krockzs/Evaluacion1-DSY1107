package cl.duoc.dsy1107.eventservice.service;
import cl.duoc.dsy1107.eventservice.dto.OtEventMessage;
import cl.duoc.dsy1107.eventservice.entity.OtEvent;
import cl.duoc.dsy1107.eventservice.repository.OtEventRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Service
public class EventConsumer {
    private final OtEventRepository repository; private final ObjectMapper mapper;
    public EventConsumer(OtEventRepository repository,ObjectMapper mapper){this.repository=repository;this.mapper=mapper;}
    @KafkaListener(topics="${app.kafka.ot-topic}")
    public void consume(OtEventMessage message) throws JsonProcessingException {
        OtEvent e=new OtEvent(); e.setOtId(message.otId()); e.setEventType(message.eventType()); e.setPayloadJson(mapper.writeValueAsString(message)); repository.save(e);
    }
}
