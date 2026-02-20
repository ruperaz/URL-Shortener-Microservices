FROM docker.io/library/maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY api-gateway/pom.xml api-gateway/pom.xml
COPY api-gateway/src api-gateway/src
RUN mvn -q -f api-gateway/pom.xml -DskipTests package

FROM docker.io/library/eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/api-gateway/target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
