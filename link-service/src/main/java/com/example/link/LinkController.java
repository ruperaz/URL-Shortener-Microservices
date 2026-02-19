package com.example.link;

import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping
class LinkController {
    private final LinkRepository repository;

    LinkController(LinkRepository repository) {this.repository = repository;}

    @PostMapping("/links")
    @PreAuthorize("hasRole('USER')")
    LinkResponse create(@RequestBody CreateRequest request, Authentication auth) {
        Jwt jwt = (Jwt) auth.getPrincipal();
        Link link = new Link();
        link.code = UUID.randomUUID().toString().substring(0, 8);
        link.longUrl = request.longUrl();
        link.ownerUserId = jwt.getSubject();
        return LinkResponse.from(repository.save(link));
    }

    @GetMapping("/links/{code}")
    LinkResponse get(@PathVariable String code, Authentication auth) {
        Link link = repository.findByCode(code).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        assertOwnerOrAdmin(link, auth);
        return LinkResponse.from(link);
    }

    @GetMapping("/links/me")
    List<LinkResponse> mine(Authentication auth) {
        Jwt jwt = (Jwt) auth.getPrincipal();
        return repository.findByOwnerUserId(jwt.getSubject()).stream().map(LinkResponse::from).toList();
    }

    @DeleteMapping("/links/{code}")
    void delete(@PathVariable String code, Authentication auth) {
        Link link = repository.findByCode(code).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        assertOwnerOrAdmin(link, auth);
        repository.delete(link);
    }

    @GetMapping("/internal/resolve/{code}")
    @PreAuthorize("hasAuthority('SCOPE_internal')")
    Map<String, Object> resolve(@PathVariable String code) {
        Link link = repository.findByCode(code).filter(l -> l.active).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        return Map.of("code", link.code, "longUrl", URI.create(link.longUrl).toString());
    }

    private void assertOwnerOrAdmin(Link link, Authentication auth) {
        Jwt jwt = (Jwt) auth.getPrincipal();
        boolean admin = auth.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
        if (!admin && !link.ownerUserId.equals(jwt.getSubject())) throw new AccessDeniedException("Not owner");
    }
}

record CreateRequest(@NotBlank String longUrl) {}
record LinkResponse(String code, String longUrl, String ownerUserId, long hits, boolean active) {
    static LinkResponse from(Link link) {return new LinkResponse(link.code, link.longUrl, link.ownerUserId, link.hits, link.active);}
}
