package cl.duoc.dsy1107.otservice.controller;

import cl.duoc.dsy1107.otservice.dto.*;
import cl.duoc.dsy1107.otservice.entity.*;
import cl.duoc.dsy1107.otservice.service.OtService;
import jakarta.validation.Valid;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/ots")
public class OtController {
    private final OtService service;
    public OtController(OtService service) { this.service = service; }

    @GetMapping public List<OtResumen> listar() { return service.listar(); }
    @GetMapping("/{id}") public Ot obtener(@PathVariable String id) { return service.obtener(id); }
    @GetMapping("/{id}/items") public List<OtItem> items(@PathVariable String id) { return service.listarItems(id); }

    @PostMapping
    public ResponseEntity<Ot> crear(@Valid @RequestBody CreateOtRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(service.crear(request));
    }

    @PutMapping("/{id}") public Ot actualizar(@PathVariable String id, @Valid @RequestBody UpdateOtRequest request) {
        return service.actualizar(id, request);
    }

    @DeleteMapping("/{id}") public ResponseEntity<Void> eliminar(@PathVariable String id) {
        service.eliminar(id); return ResponseEntity.noContent().build();
    }

    @PostMapping("/{id}/items")
    public ResponseEntity<OtItem> agregarItem(@PathVariable String id, @Valid @RequestBody CreateOtItemRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(service.agregarItem(id, request));
    }

    @DeleteMapping("/{id}/items/{itemId}")
    public ResponseEntity<Void> eliminarItem(@PathVariable String id, @PathVariable Long itemId) {
        service.eliminarItem(id, itemId); return ResponseEntity.noContent().build();
    }
}
