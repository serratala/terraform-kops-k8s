# mvn
FROM maven:alpine as build
LABEL maintainer <me@danielmonagas.codes>

WORKDIR /srv/src/

RUN apk add --no-cache git libstdc++ make gcc g++ && \
    git clone https://github.com/spring-projects/spring-boot.git && \
    cd spring-boot/spring-boot-samples/spring-boot-sample-hateoas && \
    mvn --batch-mode dependency:resolve verify

# jvm
FROM openjdk:8-jre-alpine
LABEL maintainer <me@danielmonagas.codes>

COPY --from=build /srv/src/spring-boot/spring-boot-samples/spring-boot-sample-hateoas/target/ /srv/src

EXPOSE 9000

ENTRYPOINT ["/usr/bin/java","-XX:+UnlockExperimentalVMOptions", "-XX:+UseCGroupMemoryLimitForHeap", "-jar", "/srv/src/spring-boot-sample-hateoas-2.1.0.BUILD-SNAPSHOT.jar", "--server.port=9000"]