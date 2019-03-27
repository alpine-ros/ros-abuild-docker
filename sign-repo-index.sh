#!/bin/sh

set -e

if [ ! -f ${PACKAGER_PRIVKEY} ]; then
  echo "${PACKAGER_PRIVKEY} not found" 1>&2
  exit 1
fi

index=$(find ${REPODIR} -name APKINDEX.tar.gz || true)
if [ ! -f "${index}" ]; then
  echo "APKINDEX.tar.gz not found" 1>&2
  exit 1
fi

rm -f ${index}
apk index -o ${index} `find $(dirname ${index}) -name '*.apk'`
abuild-sign -k /home/builder/.abuild/*.rsa ${index}

exit 0
