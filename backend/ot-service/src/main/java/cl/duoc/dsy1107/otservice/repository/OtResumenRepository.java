package cl.duoc.dsy1107.otservice.repository;

import cl.duoc.dsy1107.otservice.entity.OtResumen;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface OtResumenRepository extends JpaRepository<OtResumen, String> {
    List<OtResumen> findAllByOrderByCreatedAtDesc();
}
