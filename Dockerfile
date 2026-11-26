FROM node:22-bookworm AS web
WORKDIR /web
COPY Folio-Web/package.json Folio-Web/package-lock.json ./
RUN npm ci
COPY Folio-Web/ ./
RUN npm run build

FROM eclipse-temurin:25-jdk-noble AS build
WORKDIR /work
COPY Folio-Server/ /work/Folio-Server/
COPY --from=web /web/dist /work/Folio-Web/dist
WORKDIR /work/Folio-Server
RUN sed -i 's/\r$//' gradlew \
 && chmod +x gradlew \
 && ./gradlew :app:bootJar -x test -PskipWebBuild=true --no-daemon \
 && rm -rf /root/.gradle /work/Folio-Server/.gradle \
 || { rm -rf /root/.gradle /work/Folio-Server/.gradle; exit 1; }

FROM eclipse-temurin:25-jre-noble AS runtime
USER root
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       mariadb-server \
       mariadb-client \
       ffmpeg \
       tzdata \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /app /data /media /run/mysqld \
  && chown mysql:mysql /run/mysqld

COPY --from=build /work/Folio-Server/app/build/libs /tmp/libs
RUN JAR=$(ls /tmp/libs/*.jar | grep -v 'plain' | head -n1) \
  && cp "$JAR" /app/folio.jar \
  && rm -rf /tmp/libs
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
  && sed -i 's/\r$//' /entrypoint.sh

ENV SERVER_PORT=32700 \
    MYSQL_DATADIR=/data/mysql \
    MYSQL_DATABASE=folio \
    MYSQL_USER=folio \
    JAVA_OPTS="-Xms256m -Xmx512m" \
    TZ=Asia/Shanghai

VOLUME ["/data", "/media"]
EXPOSE 32700

ENTRYPOINT ["/entrypoint.sh"]
