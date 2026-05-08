## Copyright (C) 2025 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## debian:trixie-slim manifest digest as of 2026-05-08, resolved via
## the Docker Hub registry API. Re-resolve with:
##   curl -sS -H "Authorization: Bearer $(curl -s 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull' | jq -r .token)" \
##        -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
##        -D - -o /dev/null \
##        https://registry-1.docker.io/v2/library/debian/manifests/trixie-slim \
##        | grep -i docker-content-digest
FROM debian:trixie-slim@sha256:cedb1ef40439206b673ee8b33a46a03a0c9fa90bf3732f54704f99cb061d2c5a AS baseimage

ENV \
USER=user \
HOME=/home/user

COPY derivative-maker-docker-setup /usr/bin
COPY build-data/docker-entrypoint.target /etc/systemd/system
COPY build-data/docker-entrypoint.service /etc/systemd/system
COPY build-data/docker-entrypoint-stop.sh /usr/bin

RUN /usr/bin/derivative-maker-docker-setup

FROM baseimage

LABEL org.opencontainers.image.authors="adrelanos@whonix.org"
LABEL org.opencontainers.image.description="Containerization of Kicksecure/derivative-maker"
LABEL org.opencontainers.image.title="derivative-maker-docker"
LABEL org.opencontainers.image.source="https://github.com/Kicksecure/derivative-maker"
LABEL org.opencontainers.image.documentation="https://www.kicksecure.com/wiki/Dev/Build_Documentation/VM"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.vendor="ENCRYPTED SUPPORT LLC"

COPY entrypoint.sh /usr/bin
COPY derivative-maker-docker-start /usr/bin

ENTRYPOINT ["/usr/bin/entrypoint.sh"]

CMD ["/bin/bash"]
