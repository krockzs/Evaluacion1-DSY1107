package cl.duoc.dsy1107.notificationservice.config;
import org.springframework.amqp.core.*; import org.springframework.beans.factory.annotation.Value; import org.springframework.context.annotation.*; import org.springframework.amqp.support.converter.*;
@Configuration public class RabbitConfig {
 @Bean DirectExchange exchange(@Value("${app.rabbitmq.exchange}") String v){return new DirectExchange(v,true,false);} @Bean Queue queue(@Value("${app.rabbitmq.queue}") String v){return new Queue(v,true);} @Bean Binding binding(Queue q,DirectExchange e,@Value("${app.rabbitmq.routing-key}") String key){return BindingBuilder.bind(q).to(e).with(key);} @Bean MessageConverter converter(){return new Jackson2JsonMessageConverter();}
}
