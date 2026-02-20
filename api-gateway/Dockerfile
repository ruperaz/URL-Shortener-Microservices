FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml ./
RUN mvn -q install -N -DskipTests
WORKDIR /build/api-gateway
COPY api-gateway/pom.xml ./
COPY api-gateway/src src
RUN mvn -q -DskipTests package
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /build/api-gateway/target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
