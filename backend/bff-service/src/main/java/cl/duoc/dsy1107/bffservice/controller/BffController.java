package cl.duoc.dsy1107.bffservice.controller;
import cl.duoc.dsy1107.bffservice.service.BackendClient; import org.springframework.http.*; import org.springframework.security.access.prepost.PreAuthorize; import org.springframework.web.bind.annotation.*; import java.util.*;
@RestController @RequestMapping("/api")
public class BffController {
 private final BackendClient client; public BffController(BackendClient client){this.client=client;}
 @GetMapping("/me") public Map<String,Object> me(@org.springframework.security.core.annotation.AuthenticationPrincipal org.springframework.security.oauth2.jwt.Jwt jwt){return Map.of("name",Objects.toString(jwt.getClaimAsString("name"),""),"username",Objects.toString(jwt.getClaimAsString("preferred_username"),""),"roles",Optional.ofNullable(jwt.getClaimAsStringList("roles")).orElse(List.of()),"scopes",Optional.ofNullable(jwt.getClaimAsString("scp")).orElse(""));}
 @GetMapping("/ots") @PreAuthorize("hasAuthority('SCOPE_ot.read') or hasRole('TALLER_ADMIN')") public Object ots(){return client.getOts();}
 @GetMapping("/ots/{id}") @PreAuthorize("hasAuthority('SCOPE_ot.read') or hasRole('TALLER_ADMIN')") public Map<String,Object> ot(@PathVariable String id){Map<String,Object> result=new LinkedHashMap<>(); result.put("ot",client.getOt(id));result.put("items",client.getItems(id));result.put("events",client.events(id));result.put("notifications",client.notifications(id));return result;}
 @PostMapping("/ots") @PreAuthorize("hasAuthority('SCOPE_ot.write') or hasRole('TALLER_ADMIN')") public ResponseEntity<Object> create(@RequestBody Object body){return ResponseEntity.status(HttpStatus.CREATED).body(client.createOt(body));}
 @PutMapping("/ots/{id}") @PreAuthorize("hasAuthority('SCOPE_ot.write') or hasRole('TALLER_ADMIN')") public Object update(@PathVariable String id,@RequestBody Object body){return client.updateOt(id,body);}
 @DeleteMapping("/ots/{id}") @PreAuthorize("hasAuthority('SCOPE_ot.write') or hasRole('TALLER_ADMIN')") public ResponseEntity<Void> delete(@PathVariable String id){client.deleteOt(id);return ResponseEntity.noContent().build();}
 @PostMapping("/ots/{id}/items") @PreAuthorize("hasAuthority('SCOPE_ot.write') or hasRole('TALLER_ADMIN')") public ResponseEntity<Object> addItem(@PathVariable String id,@RequestBody Object body){return ResponseEntity.status(HttpStatus.CREATED).body(client.addItem(id,body));}
 @DeleteMapping("/ots/{id}/items/{itemId}") @PreAuthorize("hasAuthority('SCOPE_ot.write') or hasRole('TALLER_ADMIN')") public ResponseEntity<Void> deleteItem(@PathVariable String id,@PathVariable Long itemId){client.deleteItem(id,itemId);return ResponseEntity.noContent().build();}
}
