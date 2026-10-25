package cl.duoc.dsy1107.notificationservice.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Declaraciones estáticas de la topología de notificaciones. Sin lógica de negocio. */
@Configuration
public class RabbitConfig {
    @Bean
    public MessageConverter messageConverter() {
        return new JacksonJsonMessageConverter();
    }

    @Bean("notificationExchange")
    public DirectExchange notificationExchange(@Value("${app.rabbitmq.exchange}") String name) {
        return new DirectExchange(name, true, false);
    }

    @Bean("notificationDeadLetterExchange")
    public DirectExchange notificationDeadLetterExchange(
            @Value("${app.rabbitmq.dead-letter-exchange}") String name) {
        return new DirectExchange(name, true, false);
    }

    @Bean("notificationQueue")
    public Queue notificationQueue(
            @Value("${app.rabbitmq.queue}") String name,
            @Value("${app.rabbitmq.dead-letter-exchange}") String deadLetterExchange,
            @Value("${app.rabbitmq.dead-letter-routing-key}") String deadLetterRoutingKey) {
        return QueueBuilder.durable(name)
                .deadLetterExchange(deadLetterExchange)
                .deadLetterRoutingKey(deadLetterRoutingKey)
                .build();
    }

    @Bean("notificationDeadLetterQueue")
    public Queue notificationDeadLetterQueue(@Value("${app.rabbitmq.dead-letter-queue}") String name) {
        return QueueBuilder.durable(name).build();
    }

    @Bean("notificationBinding")
    public Binding notificationBinding(
            @Qualifier("notificationQueue") Queue queue,
            @Qualifier("notificationExchange") DirectExchange exchange,
            @Value("${app.rabbitmq.routing-key}") String routingKey) {
        return BindingBuilder.bind(queue).to(exchange).with(routingKey);
    }

    @Bean("notificationDeadLetterBinding")
    public Binding notificationDeadLetterBinding(
            @Qualifier("notificationDeadLetterQueue") Queue queue,
            @Qualifier("notificationDeadLetterExchange") DirectExchange exchange,
            @Value("${app.rabbitmq.dead-letter-routing-key}") String routingKey) {
        return BindingBuilder.bind(queue).to(exchange).with(routingKey);
    }
}
