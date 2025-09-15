FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache jq bash curl wget
RUN mkdir /opt/app
WORKDIR /opt/app

RUN JAR_VERSION=$( \
    curl -sH "Accept: application/vnd.github+json" \
      https://api.github.com/repos/Onto-Med/top-phenotypic-query/releases/latest \
      | jq -r '.tag_name | sub("^v"; "")' \
  ) && \
  wget \
    https://github.com/Onto-Med/top-phenotypic-query/releases/download/v${JAR_VERSION}/top-phenotypic-query-${JAR_VERSION}-shaded.jar \
    -O top-phenotypic-query.jar

COPY --chmod=+x ./run_queries.sh run_queries.sh

ENTRYPOINT ["/bin/bash", "run_queries.sh"]
