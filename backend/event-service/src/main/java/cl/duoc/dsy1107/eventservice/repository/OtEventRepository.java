package cl.duoc.dsy1107.eventservice.repository;
import cl.duoc.dsy1107.eventservice.entity.OtEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
public interface OtEventRepository extends JpaRepository<OtEvent,Long> {
    List<OtEvent> findAllByOrderByCreatedAtDesc();
    List<OtEvent> findByOtIdOrderByCreatedAtDesc(String otId);
}
