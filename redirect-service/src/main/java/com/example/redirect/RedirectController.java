package com.example.redirect;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.ReactiveOAuth2AuthorizedClientManager;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;

@RestController
class RedirectController {
    private final ReactiveStringRedisTemplate redis;
    private final WebClient webClient;
    private final ReactiveOAuth2AuthorizedClientManager manager;
    private final Duration ttl;

    RedirectController(ReactiveStringRedisTemplate redis, WebClient webClient, ReactiveOAuth2AuthorizedClientManager manager,
                       @Value("${redirect.cache.ttl-seconds:3600}") long ttlSec) {
        this.redis = redis; this.webClient = webClient; this.manager = manager; this.ttl = Duration.ofSeconds(ttlSec);
    }

    @GetMapping("/r/{code}")
    Mono<ResponseEntity<Void>> redirect(@PathVariable String code, @RequestHeader HttpHeaders headers) {
        return redis.opsForValue().get(code)
                .switchIfEmpty(resolveAndCache(code))
                .flatMap(url -> emitClick(code, headers).thenReturn(ResponseEntity.status(HttpStatus.FOUND).header(HttpHeaders.LOCATION, url).build()));
    }

    private Mono<String> resolveAndCache(String code) {
        return token().flatMap(token -> webClient.get().uri("http://link-service:8081/internal/resolve/{code}", code)
                        .headers(h -> h.setBearerAuth(token))
                        .retrieve().bodyToMono(Map.class)
                        .map(map -> map.get("longUrl").toString()))
                .flatMap(url -> redis.opsForValue().set(code, url, ttl).thenReturn(url));
    }

    private Mono<Void> emitClick(String code, HttpHeaders headers) {
        Map<String, Object> payload = Map.of(
                "code", code,
                "ts", Instant.now().toString(),
                "userAgent", headers.getFirst(HttpHeaders.USER_AGENT),
                "ip", headers.getFirst("X-Forwarded-For")
        );
        return token().flatMap(token -> webClient.post().uri("http://analytics-service:8083/internal/click")
                .headers(h -> h.setBearerAuth(token)).bodyValue(payload).retrieve().bodyToMono(Void.class));
    }

    private Mono<String> token() {
        Authentication principal = new AnonymousAuthenticationToken("key", "redirect-service", java.util.List.of(() -> "ROLE_SYSTEM"));
        OAuth2AuthorizeRequest request = OAuth2AuthorizeRequest.withClientRegistrationId("internal-service").principal(principal).build();
        return manager.authorize(request).map(client -> client.getAccessToken().getTokenValue());
    }
}
