package com.example.gateway;

import org.slf4j.MDC;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.context.annotation.Bean;

import java.util.UUID;

@SpringBootApplication
public class ApiGatewayApplication {
    public static void main(String[] args) {
        SpringApplication.run(ApiGatewayApplication.class, args);
    }

    @Bean
    GlobalFilter correlationFilter() {
        return (exchange, chain) -> {
            String id = exchange.getRequest().getHeaders().getFirst("X-Correlation-Id");
            if (id == null) id = UUID.randomUUID().toString();
            MDC.put("correlationId", id);
            var mutated = exchange.getRequest().mutate().header("X-Correlation-Id", id).build();
            return chain.filter(exchange.mutate().request(mutated).build()).doFinally(s -> MDC.remove("correlationId"));
        };
    }
}
