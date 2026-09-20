package cl.duoc.dsy1107.eventservice.controller;
import cl.duoc.dsy1107.eventservice.entity.OtEvent;
import cl.duoc.dsy1107.eventservice.repository.OtEventRepository;
import org.springframework.web.bind.annotation.*;
import java.util.List;
@RestController @RequestMapping("/api/events")
public class EventController {
    private final OtEventRepository repository; public EventController(OtEventRepository r){repository=r;}
    @GetMapping public List<OtEvent> all(){return repository.findAllByOrderByCreatedAtDesc();}
    @GetMapping("/ot/{otId}") public List<OtEvent> byOt(@PathVariable String otId){return repository.findByOtIdOrderByCreatedAtDesc(otId);}
}
