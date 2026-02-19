package com.example.link;

import jakarta.persistence.*;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Entity
@Table(name = "links")
class Link {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;
    @Column(unique = true, nullable = false)
    String code;
    @Column(name = "long_url", nullable = false)
    String longUrl;
    @Column(name = "owner_user_id", nullable = false)
    String ownerUserId;
    @Column(name = "created_at", nullable = false)
    Instant createdAt = Instant.now();
    long hits;
    boolean active = true;
}

interface LinkRepository extends JpaRepository<Link, Long> {
    Optional<Link> findByCode(String code);
    List<Link> findByOwnerUserId(String ownerUserId);
}
