#!/bin/sh

set -e

[ -f /etc/apk/keys/builder.rsa.pub ] || \
  (echo "/etc/apk/keys/builder.rsa.pub not found"; false)
[ -f /home/builder/.abuild/builder.rsa ] || \
  (echo "/home/builder/.abuild/builder.rsa not found"; false)

exec "$@"
