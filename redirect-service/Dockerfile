FROM docker.io/library/maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY redirect-service/pom.xml redirect-service/pom.xml
COPY redirect-service/src redirect-service/src
RUN mvn -q -f redirect-service/pom.xml -DskipTests package

FROM docker.io/library/eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/redirect-service/target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
