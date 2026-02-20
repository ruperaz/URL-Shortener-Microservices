package com.example.analytics;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.Map;

@RestController
class AnalyticsController {
    private final ClickRepository repository;

    AnalyticsController(ClickRepository repository) {this.repository = repository;}

    @PostMapping("/internal/click")
    @ResponseStatus(HttpStatus.ACCEPTED)
    @PreAuthorize("hasAuthority('SCOPE_internal')")
    void click(@RequestBody Map<String, String> payload) {
        ClickEvent e = new ClickEvent();
        e.code = payload.get("code");
        e.ts = Instant.parse(payload.getOrDefault("ts", Instant.now().toString()));
        e.userAgent = payload.get("userAgent");
        e.ip = payload.get("ip");
        repository.save(e);
    }

    @GetMapping("/analytics/{code}")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    Map<String, Object> stats(@PathVariable String code) {
        return Map.of("code", code, "totalClicks", repository.countByCode(code), "clicksByDay", repository.clicksByDay(code));
    }
}
