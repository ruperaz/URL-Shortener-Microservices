FROM docker.io/library/maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY auth-server/pom.xml auth-server/pom.xml
COPY auth-server/src auth-server/src
RUN mvn -q -f auth-server/pom.xml -DskipTests package

FROM docker.io/library/eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/auth-server/target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
