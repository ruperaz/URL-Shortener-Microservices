package com.example.auth;

import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.source.ImmutableJWKSet;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.SecurityContext;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.Resource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.server.authorization.client.JdbcRegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.ClientSettings;
import org.springframework.security.oauth2.server.authorization.settings.TokenSettings;
import org.springframework.security.web.SecurityFilterChain;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.PrivateKey;
import java.security.interfaces.RSAPrivateCrtKey;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.util.Base64;
import java.util.UUID;

@Configuration
public class SecurityConfig {

    @Bean
    SecurityFilterChain appSecurity(HttpSecurity http) throws Exception {
        return http.authorizeHttpRequests(auth -> auth
                        .requestMatchers("/.well-known/**", "/oauth2/**", "/actuator/**").permitAll()
                        .anyRequest().authenticated())
                .formLogin(Customizer.withDefaults())
                .build();
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return PasswordEncoderFactories.createDelegatingPasswordEncoder();
    }

    @Bean
    RegisteredClientRepository registeredClientRepository(JdbcTemplate jdbcTemplate,
                                                          PasswordEncoder encoder,
                                                          @Value("${auth.clients.service-client-secret}") String secret) {
        JdbcRegisteredClientRepository repo = new JdbcRegisteredClientRepository(jdbcTemplate);
        if (repo.findByClientId("gateway-public") == null) {
            RegisteredClient publicClient = RegisteredClient.withId(UUID.randomUUID().toString())
                    .clientId("gateway-public")
                    .clientAuthenticationMethod(ClientAuthenticationMethod.NONE)
                    .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                    .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
                    .redirectUri("http://localhost:8080/login/oauth2/code/gateway-public")
                    .scope("openid")
                    .scope("profile")
                    .scope("links.read")
                    .scope("links.write")
                    .clientSettings(ClientSettings.builder().requireProofKey(true).build())
                    .build();
            repo.save(publicClient);
        }
        if (repo.findByClientId("internal-service") == null) {
            RegisteredClient internalClient = RegisteredClient.withId(UUID.randomUUID().toString())
                    .clientId("internal-service")
                    .clientSecret(encoder.encode(secret))
                    .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                    .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                    .scope("internal")
                    .tokenSettings(TokenSettings.builder().accessTokenTimeToLive(Duration.ofHours(1)).build())
                    .build();
            repo.save(internalClient);
        }
        return repo;
    }

    @Bean
    JWKSource<SecurityContext> jwkSource(@Value("${auth.jwt.private-key-pem}") Resource pemResource) throws Exception {
        String pem = new String(pemResource.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        String base64 = pem.replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replaceAll("\\s", "");
        PrivateKey privateKeyDecoded = KeyFactory.getInstance("RSA")
                .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64)));
        RSAPrivateKey privateKey = (RSAPrivateKey) privateKeyDecoded;
        RSAPublicKey publicKey;
        if (privateKeyDecoded instanceof RSAPrivateCrtKey crtKey) {
            publicKey = (RSAPublicKey) KeyFactory.getInstance("RSA")
                    .generatePublic(new java.security.spec.RSAPublicKeySpec(crtKey.getModulus(), crtKey.getPublicExponent()));
        } else {
            KeyPair generated = java.security.KeyPairGenerator.getInstance("RSA").generateKeyPair();
            publicKey = (RSAPublicKey) generated.getPublic();
        }
        RSAKey rsaKey = new RSAKey.Builder(publicKey).privateKey(privateKey).keyID("main").build();
        return new ImmutableJWKSet<>(new JWKSet(rsaKey));
    }

    @Bean
    AuthorizationServerSettings authorizationServerSettings() {
        return AuthorizationServerSettings.builder().issuer("http://auth-server:9000").build();
    }
}
