package cl.duoc.dsy1107.notificationservice.repository;
import cl.duoc.dsy1107.notificationservice.entity.NotifyLog; import org.springframework.data.jpa.repository.JpaRepository; import java.util.List;
public interface NotifyLogRepository extends JpaRepository<NotifyLog,Long> { List<NotifyLog> findAllByOrderByCreatedAtDesc(); List<NotifyLog> findByOtIdOrderByCreatedAtDesc(String otId); }
