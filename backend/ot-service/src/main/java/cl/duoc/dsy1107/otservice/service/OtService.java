package cl.duoc.dsy1107.otservice.service;

import cl.duoc.dsy1107.otservice.dto.*;
import cl.duoc.dsy1107.otservice.entity.*;
import cl.duoc.dsy1107.otservice.messaging.*;
import cl.duoc.dsy1107.otservice.repository.*;
import jakarta.transaction.Transactional;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.time.Year;
import java.util.List;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@Service
public class OtService {
    private final OtRepository otRepository;
    private final OtItemRepository itemRepository;
    private final OtResumenRepository resumenRepository;
    private final OtSequenceRepository sequenceRepository;
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final RabbitTemplate rabbitTemplate;
    private final String topic;
    private final String exchange;
    private final String routingKey;

    public OtService(OtRepository otRepository, OtItemRepository itemRepository,
                     OtResumenRepository resumenRepository, OtSequenceRepository sequenceRepository,
                     KafkaTemplate<String, Object> kafkaTemplate, RabbitTemplate rabbitTemplate,
                     @Value("${app.kafka.ot-topic}") String topic,
                     @Value("${app.rabbitmq.exchange}") String exchange,
                     @Value("${app.rabbitmq.routing-key}") String routingKey) {
        this.otRepository = otRepository;
        this.itemRepository = itemRepository;
        this.resumenRepository = resumenRepository;
        this.sequenceRepository = sequenceRepository;
        this.kafkaTemplate = kafkaTemplate;
        this.rabbitTemplate = rabbitTemplate;
        this.topic = topic;
        this.exchange = exchange;
        this.routingKey = routingKey;
    }

    public List<OtResumen> listar() { return resumenRepository.findAllByOrderByCreatedAtDesc(); }

    public Ot obtener(String id) {
        return otRepository.findById(id).orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "OT no encontrada"));
    }

    public List<OtItem> listarItems(String id) {
        obtener(id);
        return itemRepository.findByOtIdOrderByItemIdAsc(id);
    }

    @Transactional
    public Ot crear(CreateOtRequest request) {
        long seq = sequenceRepository.nextValue();
        String otId = "OT-%d-%06d".formatted(Year.now().getValue(), seq);

        Ot ot = new Ot();
        ot.setOtId(otId);
        ot.setClienteId(request.clienteId());
        ot.setPatente(request.patente().toUpperCase());
        ot.setDescripcion(request.descripcion());
        ot.setTotal(request.total());
        Ot saved = otRepository.saveAndFlush(ot);

        kafkaTemplate.send(topic, saved.getOtId(), new OtEventMessage("OtCreada", saved.getOtId(), saved.getClienteId(), saved.getTotal()));
        rabbitTemplate.convertAndSend(exchange, routingKey,
            new NotificationMessage("NotificarClienteOtCreada", saved.getOtId(), saved.getClienteId(), "email"));
        return saved;
    }

    @Transactional
    public Ot actualizar(String id, UpdateOtRequest request) {
        Ot ot = obtener(id);
        if (request.clienteId() != null && !request.clienteId().isBlank()) ot.setClienteId(request.clienteId());
        if (request.patente() != null && !request.patente().isBlank()) ot.setPatente(request.patente().toUpperCase());
        if (request.descripcion() != null) ot.setDescripcion(request.descripcion());
        if (request.total() != null) ot.setTotal(request.total());
        Ot saved = otRepository.saveAndFlush(ot);
        kafkaTemplate.send(topic, saved.getOtId(), new OtEventMessage("OtActualizada", saved.getOtId(), saved.getClienteId(), saved.getTotal()));
        return saved;
    }

    @Transactional
    public void eliminar(String id) {
        Ot ot = obtener(id);
        otRepository.delete(ot);
        kafkaTemplate.send(topic, id, new OtEventMessage("OtEliminada", id, ot.getClienteId(), ot.getTotal()));
    }

    @Transactional
    public OtItem agregarItem(String otId, CreateOtItemRequest request) {
        obtener(otId);
        OtItem item = new OtItem();
        item.setOtId(otId);
        item.setConcepto(request.concepto());
        item.setCantidad(request.cantidad());
        item.setPrecioUnit(request.precioUnit());
        OtItem saved = itemRepository.saveAndFlush(item);
        kafkaTemplate.send(topic, otId, new OtEventMessage("ItemAgregado", otId, null, saved.getSubtotal()));
        return saved;
    }

    @Transactional
    public void eliminarItem(String otId, Long itemId) {
        obtener(otId);
        OtItem item = itemRepository.findById(itemId).orElseThrow(() -> new ResponseStatusException(NOT_FOUND, "Ítem no encontrado"));
        if (!otId.equals(item.getOtId())) throw new ResponseStatusException(NOT_FOUND, "Ítem no pertenece a la OT");
        itemRepository.delete(item);
        kafkaTemplate.send(topic, otId, new OtEventMessage("ItemEliminado", otId, null, null));
    }
}
