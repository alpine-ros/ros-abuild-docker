#!/bin/sh

set -e

if [ $# -lt 1 ]; then
  echo "usage: $0 REPONAME"
  exit 1
fi

repo=$1

if [ ! -z ${CUSTOM_APK_REPOS} ]; then
  for repo in ${CUSTOM_APK_REPOS}; do
    echo $repo >> /etc/apk/repositories
  done
fi

rosdep update
sudo apk update

[ -f ${PACKAGER_PRIVKEY} ] || abuild-keygen -a -i -n

mkdir -p ${APORTSDIR}/${repo}
mkdir -p ${REPODIR}

manifests=`find ${SRCDIR}/${repo} -name "package.xml"`
for manifest in ${manifests}; do
  pkgpath=$(dirname ${manifest})
  pkgname=$(basename ${pkgpath})

  # Copy files with filter
  mkdir -p ${APORTSDIR}/${repo}/${pkgname}
  files=$(ls -1A ${pkgpath})
  for file in ${files}; do
    if [ $file == ".git" ]; then continue; fi

    cp -r ${pkgpath}/${file} ${APORTSDIR}/${repo}/${pkgname}/${file}
  done

  /generate_apkbuild.py kinetic ${APORTSDIR}/${repo}/${pkgname}/package.xml --src | tee ${APORTSDIR}/${repo}/${pkgname}/APKBUILD
done

buildrepo -a ${APORTSDIR} -d ${REPODIR} ${repo}
