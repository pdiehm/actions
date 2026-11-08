FROM alpine:3.24.4

RUN apk update && apk upgrade && apk add bash git crane
COPY main.sh /main.sh

RUN adduser -DHu 1001 runner
USER runner

ENTRYPOINT ["/bin/bash", "/main.sh"]
