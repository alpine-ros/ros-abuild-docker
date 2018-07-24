FROM alpine:3.8

RUN apk add --no-cache alpine-sdk sudo \
  && adduser -G abuild -D builder \
  && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
  && mkdir -p /packages \
  && mkdir -p /abuilds \
  && chown builder:abuild /packages /abuilds

RUN apk add --no-cache python2 py2-pip \
  && pip install \
    git+https://github.com/at-wat/rospkg.git@fix-alpine-detect \
    git+https://github.com/at-wat/rosdep.git@alpine-installer \
    rosinstall_generator \
    wstool

RUN echo "http://alpine-ros-experimental.dev-sq.work/v3.8/backports" >> /etc/apk/repositories \
  && echo $'-----BEGIN PUBLIC KEY-----\n\
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnSO+a+rIaTorOowj3c8e\n\
5St89puiGJ54QmOW9faDsTcIWhycl4bM5lftp8IdcpKadcnaihwLtMLeaHNJvMIP\n\
XrgEEoaPzEuvLf6kF4IN8HJoFGDhmuW4lTuJNfsOIDWtLBH0EN+3lPuCPmNkULeo\n\
iS3Sdjz10eB26TYiM9pbMQnm7zPnDSYSLm9aCy+gumcoyCt1K1OY3A9E3EayYdk1\n\
9nk9IQKA3vgdPGCEh+kjAjnmVxwV72rDdEwie0RkIyJ/al3onRLAfN4+FGkX2CFb\n\
a17OJ4wWWaPvOq8PshcTZ2P3Me8kTCWr/fczjzq+8hB0MNEqfuENoSyZhmCypEuy\n\
ewIDAQAB\n\
-----END PUBLIC KEY-----' > /etc/apk/keys/builder@alpine-ros-experimental.rsa.pub

RUN rosdep init \
  && sed -i -e 's/ros\/rosdistro\/master/at-wat\/rosdistro\/alpine-custom-apk/' /etc/ros/rosdep/sources.list.d/20-default.list

RUN mkdir -p /var/cache/apk \
  && ln -s /var/cache/apk /etc/apk/cache

WORKDIR /abuilds
USER builder
RUN rosdep update

ENV PACKAGER_PRIVKEY="/home/builder/.abuild/builder@alpine-ros-experimental.rsa"
ENV REPODEST=/packages

COPY entrypoint.sh /
COPY all.sh /
COPY scripts /scripts
COPY ros_packages.list /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/sh"]
