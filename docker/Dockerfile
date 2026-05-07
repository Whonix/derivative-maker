## Copyright (C) 2025 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

FROM debian:trixie-slim AS baseimage

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
