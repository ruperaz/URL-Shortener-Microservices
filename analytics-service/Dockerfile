FROM docker.io/library/maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY analytics-service/pom.xml analytics-service/pom.xml
COPY analytics-service/src analytics-service/src
RUN mvn -q -pl analytics-service -am -DskipTests package

FROM docker.io/library/eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/analytics-service/target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
