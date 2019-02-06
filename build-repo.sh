#!/bin/sh

set -e

repo=${ROS_DISTRO}

if [ ! -f ${PACKAGER_PRIVKEY} ]; then
  abuild-keygen -a -i -n

  # Re-sign packages if private key is updated
  index=$(find ${REPODIR} -name APKINDEX.tar.gz || true)
  if [ -f "${index}" ]; then
    rm -f ${index}
    apk index -o ${index} `find $(dirname ${index}) -name '*.apk'`
    abuild-sign -k /home/builder/.abuild/*.rsa ${index}
  fi
fi

mkdir -p ${APORTSDIR}/${repo}
mkdir -p ${REPODIR}
mkdir -p ${LOGDIR}

summary_file=${LOGDIR}/summary.log
full_log_file=${LOGDIR}/full.log


# Update repositories

if [ ! -z ${CUSTOM_APK_REPOS} ]; then
  for r in ${CUSTOM_APK_REPOS}; do
    echo $r >> /etc/apk/repositories
  done
fi
echo "${REPODIR}/${repo}" | sudo tee -a /etc/apk/repositories
sudo apk update
rosdep update


# Generate APKBUILDs

manifests=`find ${SRCDIR} -name "package.xml"`
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

  /generate_apkbuild.py ${repo} ${APORTSDIR}/${repo}/${pkgname}/package.xml --src | tee ${APORTSDIR}/${repo}/${pkgname}/APKBUILD
done

rm -f $(find ${APORTSDIR} -name "ros-abuild-build.log")
rm -f $(find ${APORTSDIR} -name "ros-abuild-check.log")
rm -f $(find ${APORTSDIR} -name "ros-abuild-status.log")


# Build everything

GENERATE_BUILD_LOGS=yes buildrepo -k ${repo} | tee ${full_log_file}


# Summarize build result

function summarize_error() {
  error_text=$(grep -A5 -i -E "$2" $1 || true)
  lines=$(echo -n "${error_text}" | wc -l)

  # print summary
  if [ ${lines} -lt 1 ]; then
    echo 'no build error detected'
  else
    echo "${error_text}" | head -n30
    if [ ${lines} -gt 30 ]; then
      echo "error log exceeded 30 lines (total ${lines} lines)"
    fi
  fi
}

rm -f ${summary_file}

echo "## Summary" >> ${summary_file}
echo '```' >> ${summary_file}
tail -n6 ${full_log_file} >> ${summary_file}
echo '```' >> ${summary_file}

for manifest in ${manifests}; do
  srcpath=$(dirname ${manifest})
  pkgname=$(basename ${srcpath})
  pkgpath=${APORTSDIR}/${repo}/${pkgname}

  echo >> ${summary_file}
  echo "## $pkgname" >> ${summary_file}

  if [ ! -f ${pkgpath}/apk-build-temporary/ros-abuild-status.log ]; then
    echo "Failed to start build or already been built" >> ${summary_file}
    continue
  fi
  if grep "finished" ${pkgpath}/apk-build-temporary/ros-abuild-status.log > /dev/null; then
    echo "Build succeeded" >> ${summary_file}
    continue
  fi

  echo "### Build log" >> ${summary_file}
  if [ ! -f ${pkgpath}/apk-build-temporary/ros-abuild-build.log ]; then
    echo "Build log not found" >> ${summary_file}
    continue
  fi
  echo "\`\`\`" >> ${summary_file}
  summarize_error ${pkgpath}/apk-build-temporary/ros-abuild-build.log "error" >> ${summary_file}
  echo "\`\`\`" >> ${summary_file}

  if [ -f ${pkgpath}/apk-build-temporary/ros-abuild-check.log ]; then
    echo "### Check log" >> ${summary_file}
    echo '```' >> ${summary_file}
    summarize_error ${pkgpath}/apk-build-temporary/ros-abuild-check.log "(error|failure)" >> ${summary_file}
    echo '```' >> ${summary_file}
    continue
  fi
done

echo
echo "---"
cat ${summary_file}