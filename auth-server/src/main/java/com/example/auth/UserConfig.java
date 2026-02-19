package com.example.auth;

import jakarta.persistence.*;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;

@Configuration
public class UserConfig {
    @Bean
    UserDetailsService userDetailsService(UserAccountRepository repository) {
        return username -> repository.findByUsername(username)
                .map(u -> User.withUsername(u.username).password(u.passwordHash).roles(u.role.replace("ROLE_", "")).build())
                .orElseThrow();
    }

    @Bean
    CommandLineRunner seedUsers(UserAccountRepository repo, PasswordEncoder encoder) {
        return args -> {
            if (repo.findByUsername("user1").isEmpty()) repo.save(new UserAccount("user1", encoder.encode("password1"), "ROLE_USER"));
            if (repo.findByUsername("admin").isEmpty()) repo.save(new UserAccount("admin", encoder.encode("password1"), "ROLE_ADMIN"));
        };
    }
}

@Entity
@Table(name = "users")
class UserAccount {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;
    @Column(unique = true, nullable = false)
    String username;
    @Column(name = "password_hash", nullable = false)
    String passwordHash;
    @Column(nullable = false)
    String role;

    public UserAccount() {}
    public UserAccount(String username, String passwordHash, String role) {this.username = username; this.passwordHash = passwordHash; this.role = role;}
}

interface UserAccountRepository extends JpaRepository<UserAccount, Long> {
    Optional<UserAccount> findByUsername(String username);
}
