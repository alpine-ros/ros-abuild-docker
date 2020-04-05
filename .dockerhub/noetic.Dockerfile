FROM alpine:3.11

ENV ROS_DISTRO=noetic

RUN apk add --no-cache alpine-sdk lua-aports sudo \
  && adduser -G abuild -D builder \
  && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN apk add --no-cache python3 py3-pip py3-yaml \
  && pip3 install \
    requests \
    rosdep \
    rosinstall_generator \
    rospkg \
    wstool

ARG ROS_PYTHON_VERSION=2
ENV ROS_PYTHON_VERSION=${ROS_PYTHON_VERSION}

RUN echo "http://alpine-ros-experimental.dev-sq.work/v3.11/backports" >> /etc/apk/repositories \
  && echo "http://alpine-ros-experimental.dev-sq.work/v3.11/ros/noetic" >> /etc/apk/repositories \
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
  && sed -i -e 's|ros/rosdistro/master|alpine-ros/rosdistro/alpine-custom-apk|' /etc/ros/rosdep/sources.list.d/20-default.list

RUN mkdir -p /var/cache/apk \
  && ln -s /var/cache/apk /etc/apk/cache

# Workaround for rospack on fakeroot
RUN mkdir -p /root/.ros \
  && chmod a+x /root \
  && chmod a+rwx /root/.ros

COPY setup.py /tmp/genapkbuild/
COPY generate_rospkg_apkbuild /tmp/genapkbuild/generate_rospkg_apkbuild
RUN pip3 install /tmp/genapkbuild

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

RUN mkdir -p ${APORTSDIR} ${REPODIR} ${LOGDIR} ${SRCDIR} \
  && chmod a+rwx ${APORTSDIR} ${REPODIR} ${LOGDIR} ${SRCDIR}

VOLUME ${SRCDIR}
WORKDIR ${SRCDIR}

USER builder
ENTRYPOINT ["/build-repo.sh"]
