FROM alpine:3.8

RUN apk add --no-cache alpine-sdk sudo \
  && adduser -G abuild -D builder \
  && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
  && mkdir -p /packages \
  && mkdir -p /abuilds \
  && chown builder:abuild /packages /abuilds

WORKDIR /abuilds
USER builder

ENV PACKAGER_PRIVKEY="/home/builder/.abuild/builder@alpine-ros-experimental.rsa"
ENV REPODEST=/packages

COPY entrypoint.sh /
COPY all.sh /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/sh"]
