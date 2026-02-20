FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml ./
RUN mvn -q install -N -DskipTests
WORKDIR /build/auth-server
COPY auth-server/pom.xml ./
COPY auth-server/src src
RUN mvn -q -DskipTests package
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /build/auth-server/target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
