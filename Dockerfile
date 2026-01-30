FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache jq bash curl wget gettext
RUN mkdir /opt/app
WORKDIR /opt/app

ENV DB_HOST=host.docker.internal
ENV DB_PORT=5432
ENV DB_NAME=cds_hub_db
ENV DB_USER=db2dataprocessor_user

ADD "https://api.github.com/repos/Onto-Med/top-phenotypic-query/releases/latest" latest_release
RUN JAR_VERSION=$(jq -r '.tag_name | sub("^v"; "")' latest_release) \
  && wget \
    https://github.com/Onto-Med/top-phenotypic-query/releases/download/v${JAR_VERSION}/top-phenotypic-query-${JAR_VERSION}-shaded.jar \
    -q -O top-phenotypic-query.jar \
  && rm latest_release

COPY --chmod=+x ./run_queries.sh run_queries.sh
COPY models models
COPY adapter.yml.tpl adapter.yml

CMD ["/bin/bash", "run_queries.sh"]
