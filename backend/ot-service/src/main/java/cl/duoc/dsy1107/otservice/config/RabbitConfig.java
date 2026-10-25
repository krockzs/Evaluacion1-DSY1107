package cl.duoc.dsy1107.otservice.config;

import org.springframework.amqp.core.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;

@Configuration
public class RabbitConfig {
    @Bean
    public MessageConverter messageConverter() { return new JacksonJsonMessageConverter(); }

    @Bean
    public DirectExchange otNotificationExchange(@Value("${app.rabbitmq.exchange}") String exchange) {
        return new DirectExchange(exchange, true, false);
    }
}
