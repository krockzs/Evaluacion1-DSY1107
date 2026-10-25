package cl.duoc.dsy1107.rabbit_admin_service.service;

import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import cl.duoc.dsy1107.rabbit_admin_service.dto.AdminRequests.*;

@Service
public class RabbitAdminService {
    private final RabbitManagementClient api;
    private final String vhost;
    public RabbitAdminService(RabbitManagementClient api,@Value("${app.rabbit-admin.vhost}") String vhost){this.api=api;this.vhost=RabbitManagementClient.segment(vhost);}
    private String queues(){return "api/queues/"+vhost;}
    private String exchanges(){return "api/exchanges/"+vhost;}
    private String enc(String s){return RabbitManagementClient.segment(s);}
    private static void validName(String s){
        if(s == null || s.isBlank() || s.length()>120 || s.startsWith("amq.") || !s.matches("[A-Za-z0-9][A-Za-z0-9._-]*"))
            throw new IllegalArgumentException("Nombre inválido o reservado");
    }
    public Object listQueues(){return api.call("GET",queues(),null);}
    public Object queue(String name){validName(name);return api.call("GET",queues()+"/"+enc(name),null);}
    public Object createQueue(QueueRequest r){
        validName(r.name());
        String path=queues()+"/"+enc(r.name());
        try {
            Object existing=api.call("GET",path,null);
            return Map.of("status",200,"created",false,"message","La cola ya existe; se conservó su configuración","queue",existing);
        } catch (RabbitManagementClient.RabbitAdminUpstreamException ex) {
            if(ex.status!=404) throw ex;
        }
        return api.call("PUT",path,Map.of("durable",r.durable(),"auto_delete",false,"arguments",Map.of()));
    }
    public Object deleteQueue(String name){validName(name);return api.call("DELETE",queues()+"/"+enc(name),null);}
    public Object listExchanges(){return api.call("GET",exchanges(),null);}
    public Object createExchange(ExchangeRequest r){
        validName(r.name());
        String path=exchanges()+"/"+enc(r.name());
        try {
            Object existing=api.call("GET",path,null);
            return Map.of("status",200,"created",false,"message","El exchange ya existe; se conservó su configuración","exchange",existing);
        } catch (RabbitManagementClient.RabbitAdminUpstreamException ex) {
            if(ex.status!=404) throw ex;
        }
        return api.call("PUT",path,Map.of("type",r.type(),"durable",r.durable(),"auto_delete",false,"internal",false,"arguments",Map.of()));
    }
    public Object deleteExchange(String name){validName(name);return api.call("DELETE",exchanges()+"/"+enc(name),null);}
    public Object listBindings(){return api.call("GET","api/bindings/"+vhost,null);}
    public Object createBinding(BindingRequest r){validName(r.source());validName(r.destination());return api.call("POST","api/bindings/"+vhost+"/e/"+enc(r.source())+"/q/"+enc(r.destination()),Map.of("routing_key",r.routingKey(),"arguments",Map.of()));}
    public Object deleteBinding(String source,String queue,String propertiesKey){validName(source);validName(queue);if(propertiesKey==null || propertiesKey.isBlank())throw new IllegalArgumentException("propertiesKey requerido");return api.call("DELETE","api/bindings/"+vhost+"/e/"+enc(source)+"/q/"+enc(queue)+"/"+enc(propertiesKey),null);}
    public Object publish(PublishRequest r){validName(r.exchange());if(r.payload().length()>16384)throw new IllegalArgumentException("Payload supera 16 KiB");return api.call("POST",exchanges()+"/"+enc(r.exchange())+"/publish",Map.of("properties",Map.of("content_type","application/json"),"routing_key",r.routingKey()==null?"":r.routingKey(),"payload",r.payload(),"payload_encoding","string"));}
    /** RabbitMQ Management get usa ack_requeue_true: NO es una lectura totalmente pasiva. */
    public Object peek(String name,int count){validName(name);if(count<1||count>10)throw new IllegalArgumentException("count debe ser 1..10");return api.call("POST",queues()+"/"+enc(name)+"/get",Map.of("count",count,"ackmode","ack_requeue_true","encoding","auto","truncate",8192));}
}
