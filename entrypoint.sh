#!/bin/sh

set -e

[ -f /etc/apk/keys/builder@alpine-ros-experimental.rsa.pub ] || \
  (echo "/etc/apk/keys/builder@alpine-ros-experimental.rsa.pub not found"; false)
[ -f /home/builder/.abuild/builder@alpine-ros-experimental.rsa ] || \
  (echo "/home/builder/.abuild/builder@alpine-ros-experimental.rsa not found"; false)

exec "$@"
