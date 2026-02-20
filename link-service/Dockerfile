FROM docker.io/library/maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml ./
COPY link-service/pom.xml link-service/pom.xml
COPY link-service/src link-service/src
RUN mvn -q -pl link-service -am -DskipTests package

FROM docker.io/library/eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /workspace/link-service/target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app/app.jar"]
