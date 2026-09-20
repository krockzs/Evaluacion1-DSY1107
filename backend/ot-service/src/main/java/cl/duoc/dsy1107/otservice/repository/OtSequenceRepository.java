package cl.duoc.dsy1107.otservice.repository;

import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Repository;

@Repository
public class OtSequenceRepository {
    private final EntityManager entityManager;
    public OtSequenceRepository(EntityManager entityManager) { this.entityManager = entityManager; }
    public long nextValue() {
        Number value = (Number) entityManager.createNativeQuery("SELECT SEQ_OT.NEXTVAL FROM DUAL").getSingleResult();
        return value.longValue();
    }
}
