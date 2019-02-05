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

flatsrc=/flatsrc
apkdir=/apkdir

sudo mkdir -p ${flatsrc}/${repo}
sudo chown -R builder ${flatsrc}

manifests=`find ${repo} -name "package.xml"`
for manifest in $manifests; do
  pkgpath=$(dirname $manifest)
  pkgname=$(basename $pkgpath)
  cp -r ${pkgpath} ${flatsrc}/${repo}/${pkgname}
  /generate_apkbuild.py kinetic ${flatsrc}/${repo}/${pkgname}/package.xml --src | tee ${flatsrc}/${repo}/${pkgname}/APKBUILD
done

sudo chown builder ${apkdir}
mkdir -p ${apkdir}/${repo}

buildrepo -a ${flatsrc} -d ${apkdir} ${repo}
