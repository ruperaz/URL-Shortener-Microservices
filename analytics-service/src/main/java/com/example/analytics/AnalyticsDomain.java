package com.example.analytics;

import jakarta.persistence.*;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@Entity
@Table(name = "click_events")
class ClickEvent {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) Long id;
    String code;
    Instant ts;
    String userAgent;
    String ip;
}

interface ClickRepository extends JpaRepository<ClickEvent, Long> {
    long countByCode(String code);
    @Query("select cast(c.ts as date), count(c) from ClickEvent c where c.code = :code group by cast(c.ts as date)")
    List<Object[]> clicksByDayRaw(String code);
    default Map<LocalDate, Long> clicksByDay(String code) {
        return clicksByDayRaw(code).stream().collect(java.util.stream.Collectors.toMap(r -> (LocalDate) r[0], r -> (Long) r[1]));
    }
}
