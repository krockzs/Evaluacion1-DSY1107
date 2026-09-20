package cl.duoc.dsy1107.otservice.repository;

import cl.duoc.dsy1107.otservice.entity.OtItem;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface OtItemRepository extends JpaRepository<OtItem, Long> {
    List<OtItem> findByOtIdOrderByItemIdAsc(String otId);
}
