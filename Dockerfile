# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.17
FROM alpine:${ALPINE_VERSION}
ARG ALPINE_VERSION=3.17
ARG ROS_DISTRO=noetic

ENV ROS_DISTRO=${ROS_DISTRO} \
  ALPINE_VERSION=${ALPINE_VERSION}

RUN apk add --no-cache alpine-sdk lua-aports sudo \
  && adduser -G abuild -D builder \
  && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ARG ROS_PYTHON_VERSION=3
ENV ROS_PYTHON_VERSION=${ROS_PYTHON_VERSION}

RUN echo "http://alpine-ros.seqsense.org/v${ALPINE_VERSION}/backports" >> /etc/apk/repositories \
  && echo "http://alpine-ros.seqsense.org/v${ALPINE_VERSION}/ros/${ROS_DISTRO}" >> /etc/apk/repositories
COPY <<EOF /etc/apk/keys/builder@alpine-ros-experimental.rsa.pub
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnSO+a+rIaTorOowj3c8e
5St89puiGJ54QmOW9faDsTcIWhycl4bM5lftp8IdcpKadcnaihwLtMLeaHNJvMIP
XrgEEoaPzEuvLf6kF4IN8HJoFGDhmuW4lTuJNfsOIDWtLBH0EN+3lPuCPmNkULeo
iS3Sdjz10eB26TYiM9pbMQnm7zPnDSYSLm9aCy+gumcoyCt1K1OY3A9E3EayYdk1
9nk9IQKA3vgdPGCEh+kjAjnmVxwV72rDdEwie0RkIyJ/al3onRLAfN4+FGkX2CFb
a17OJ4wWWaPvOq8PshcTZ2P3Me8kTCWr/fczjzq+8hB0MNEqfuENoSyZhmCypEuy
ewIDAQAB
-----END PUBLIC KEY-----
EOF

RUN apk add --no-cache \
    ccache \
    py3-pip \
    py3-requests \
    py3-rosdep \
    py3-rosinstall-generator \
    py3-rospkg \
    py3-vcstool \
    py3-yaml \
    python3 \
    sed

RUN rosdep init \
  && sed -i -e 's|ros/rosdistro/master|alpine-ros/rosdistro/alpine-custom-apk|' /etc/ros/rosdep/sources.list.d/20-default.list

RUN mkdir -p /var/cache/apk \
  && ln -s /var/cache/apk /etc/apk/cache

# Workaround for rospack on fakeroot
RUN mkdir -p /root/.ros \
  && chmod a+x /root \
  && chmod a+rwx /root/.ros

COPY setup.py /tmp/genapkbuild/
COPY generate_rospkg_apkbuild /tmp/genapkbuild/generate_rospkg_apkbuild
RUN pip3 install $([ "${ALPINE_VERSION}" != '3.17' ] && echo -n '--break-system-packages') /tmp/genapkbuild

COPY build-repo.sh /
COPY sign-repo-index.sh /

ENV HOME="/home/builder"
ENV PACKAGER_PRIVKEY="${HOME}/.abuild/builder@alpine-ros-experimental.rsa"
ENV APORTSDIR="/aports"
ENV REPODIR="/packages"
ENV LOGDIR="/logs"
ENV SRCDIR="/src"
ENV TZ=UTC
ENV FORCE_LOCAL_VERSION=no
ENV SKIP_ROSDEP_UPDATE=false

RUN mkdir -p ${APORTSDIR} ${REPODIR} ${LOGDIR} ${SRCDIR} \
  && chmod a+rwx ${APORTSDIR} ${REPODIR} ${LOGDIR} ${SRCDIR}

VOLUME ${SRCDIR}
WORKDIR ${SRCDIR}

RUN mkdir -p /var/cache/apk \
  && ln -s /var/cache/apk /etc/apk/cache \
  && mkdir -p ${HOME}/.ros/rosdep

USER builder

ENV CCACHE_DIR=/ccache

VOLUME /ccache
VOLUME /var/cache/apk
VOLUME ${HOME}/.ros/rosdep

ENTRYPOINT ["/build-repo.sh"]
