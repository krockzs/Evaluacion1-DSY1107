package cl.duoc.dsy1107.rabbit_admin_service.controller;

import cl.duoc.dsy1107.rabbit_admin_service.dto.AdminRequests.*;
import cl.duoc.dsy1107.rabbit_admin_service.service.RabbitAdminService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin")
@Validated
public class RabbitAdminController {
    private final RabbitAdminService service;
    public RabbitAdminController(RabbitAdminService service){this.service=service;}
    @GetMapping("/queues") public Object queues(){return service.listQueues();}
    @GetMapping("/queues/{name}") public Object queue(@PathVariable String name){return service.queue(name);}
    @PostMapping("/queues") public Object createQueue(@Valid @RequestBody QueueRequest input){return service.createQueue(input);}
    @DeleteMapping("/queues/{name}") public Object deleteQueue(@PathVariable String name){return service.deleteQueue(name);}
    @GetMapping("/queues/{name}/messages") public Object peek(@PathVariable String name,@RequestParam(defaultValue="1") @Min(1) @Max(10) int count){return service.peek(name,count);}
    @GetMapping("/exchanges") public Object exchanges(){return service.listExchanges();}
    @PostMapping("/exchanges") public Object createExchange(@Valid @RequestBody ExchangeRequest input){return service.createExchange(input);}
    @DeleteMapping("/exchanges/{name}") public Object deleteExchange(@PathVariable String name){return service.deleteExchange(name);}
    @GetMapping("/bindings") public Object bindings(){return service.listBindings();}
    @PostMapping("/bindings") public Object createBinding(@Valid @RequestBody BindingRequest input){return service.createBinding(input);}
    @DeleteMapping("/bindings/{source}/{queue}/{propertiesKey}") public Object deleteBinding(@PathVariable String source,@PathVariable String queue,@PathVariable String propertiesKey){return service.deleteBinding(source,queue,propertiesKey);}
    @PostMapping("/publish") public Object publish(@Valid @RequestBody PublishRequest input){return service.publish(input);}
}
