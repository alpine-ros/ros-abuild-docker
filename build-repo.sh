#!/bin/sh

set -e

umask ${UMASK:-0000}
sudo chmod a+rwx \
  /var/cache/apk \
  ${CCACHE_DIR} \
  ${HOME}/.ros \
  ${HOME}/.ros/rosdep

build_subdir=abuild

# Validate environment variables

case "${FORCE_LOCAL_VERSION}" in
  "")
    FORCE_LOCAL_VERSION=no
    ;;
  yes)
    ;;
  no)
    ;;
  *)
    echo "FORCE_LOCAL_VERSION must be one of: \"yes\", \"no\", \"\" (default: \"no\")"
    exit 1
    ;;
esac

case "${VERSION_PER_SUBPACKAGE}" in
  "")
    VERSION_PER_SUBPACKAGE=no
    ;;
  yes)
    ;;
  full)
    ;;
  no)
    ;;
  *)
    echo "VERSION_PER_SUBPACKAGE must be one of:"
    echo "   \"yes\": versioned based on the latest commit of the subpackage (merge commit is ignored)"
    echo "  \"full\": versioned based on the latest commit of the subpackage (including merge commit)"
    echo "    \"no\": versioned based on the latest commit of the repository"
    echo "      \"\": use default (\"no\")"
    exit 1
    ;;
esac

case "${ENABLE_CCACHE}" in
  "")
    ENABLE_CCACHE=no
    ;;
  yes)
    ;;
  no)
    ;;
  *)
    echo "ENABLE_CCACHE must be one of: \"yes\", \"no\", \"\" (default: \"no\")"
    exit 1
    ;;
esac

case "${SKIP_ROSDEP_UPDATE}" in
  "")
    SKIP_ROSDEP_UPDATE=false
    ;;
  yes|true)
    SKIP_ROSDEP_UPDATE=true
    ;;
  no|false)
    SKIP_ROSDEP_UPDATE=false
    ;;
  *)
    echo "SKIP_ROSDEP_UPDATE must be one of: \"yes\", \"no\", \"\" (default: \"no\")"
    # Accept true/false as well for backward compatibility.
    exit 1
    ;;
esac


# Setup environment variables

if [ ! -z "${JOBS}" ]; then
  sudo sed -i "s/export JOBS=.*/export JOBS=${JOBS}/" /etc/abuild.conf
fi

sudo sed -i 's/export MAKEFLAGS=.*/export MAKEFLAGS="-j$JOBS -l$JOBS"/' /etc/abuild.conf

if [ ! -z "${CFLAGS}" ]; then
  echo "Overwriting CFLAGS"
  echo "original:"
  echo "---"
  head -n 4 /etc/abuild.conf
  sudo sed -i "s/export CFLAGS=\"-Os -fomit-frame-pointer\"/export CFLAGS=\"${CFLAGS}\"/" /etc/abuild.conf
  echo "---"
  echo "updated:"
  echo "---"
  head -n 4 /etc/abuild.conf
  echo "---"
  echo
fi

if [ ${ENABLE_CCACHE} = "yes" ]
then
  echo "ccache enabled (cache dir: ${CCACHE_DIR})"
  export CC=/usr/lib/ccache/bin/gcc
  export CXX=/usr/lib/ccache/bin/g++
fi

repo=${ROS_DISTRO}

if [ ! -f "${PACKAGER_PRIVKEY}" ]; then
  abuild-keygen -a -i -n

  # Re-sign packages if private key is updated
  index=$(find ${REPODIR} -name APKINDEX.tar.gz || true)
  if [ -f "${index}" ]; then
    rm -f ${index}
    apk index -o ${index} $(find $(dirname ${index}) -name '*.apk')
    abuild-sign -k /home/builder/.abuild/*.rsa ${index}
  fi
fi

mkdir -p ${APORTSDIR}/${repo}
mkdir -p ${REPODIR}
mkdir -p ${LOGDIR}

extsrc=${HOME}/extsrc
mkdir -p ${extsrc}

summary_file=${LOGDIR}/summary.log
full_log_file=${LOGDIR}/full.log
apk_list_file=${LOGDIR}/apk_list.log


case "${VERSION_PER_SUBPACKAGE}" in
  "yes")
    echo "VERSION_PER_SUBPACKAGE: enabled"
    commit_date_option="."
    ext_pkg_option=
    ;;
  "full")
    echo "VERSION_PER_SUBPACKAGE: enabled (including merge commit)"
    commit_date_option="--full-history ."
    ext_pkg_option=
    ;;
  *)
    commit_date_option=
    ext_pkg_option="--shallow"
    ;;
esac


# Update repositories

if [ ! -z "${CUSTOM_APK_REPOS}" ]; then
  for r in ${CUSTOM_APK_REPOS}; do
    echo "CUSTOM_APK_REPO: ${r}"
    echo $r | sudo tee -a /etc/apk/repositories
  done
fi
echo "${REPODIR}/${repo}" | sudo tee -a /etc/apk/repositories
sudo apk update

if [ ! -f ${HOME}/.ros/rosdep/sources.cache/index ] || ! ${SKIP_ROSDEP_UPDATE:-false}; then
  rosdep update
fi


# Clone packages if .rosinstall is provided

ext_deps=$(find ${SRCDIR} -name "*.rosinstall" || true)
for dep in ${ext_deps}; do
  # skip empty and all commented out .rosinstall files
  if [ $(cat ${dep} | sed '/^\s*#/d;/^\s*$/d' | wc -l) -eq 0 ]; then
    echo "Skipping ${dep}: no repository found"
    continue
  fi
  if ! vcs validate --input ${dep}; then
    echo "${dep} is invalid"
    exit 1
  fi
  vcs import --input ${dep} ${ext_pkg_option} ${VCS_OPTIONS} --workers 4 ${extsrc}
done


# Allow to handle git repositories owned by outer container user

for dir in $(find ${SRCDIR} -name ".git" -type d); do
  git config --global --add safe.directory $(dirname ${dir})
done


# Generate APKBUILDs

error=false

manifests="$(find ${SRCDIR} -name "package.xml") $(find ${extsrc} -name "package.xml")"
for manifest in ${manifests}; do
  echo +++++++++++++++++++++++++
  echo "manifest: ${manifest}"
  pkgpath=$(dirname ${manifest})
  pkgname=$(basename ${pkgpath})

  echo "latest commit:"
  git_log_opts="-n1 HEAD ${commit_date_option}"
  git --no-pager -C ${pkgpath} log ${git_log_opts}
  echo
  commit_date=$(git --no-pager -C ${pkgpath} log \
                --format=%ad --date=format-local:'%Y%m%d%H%M%S' ${git_log_opts})

  # Copy files with filter
  mkdir -p ${APORTSDIR}/${repo}/${pkgname}
  files=$(ls -1A ${pkgpath})
  for file in ${files}; do
    if [ $file = ".git" ]; then continue; fi

    cp -r ${pkgpath}/${file} ${APORTSDIR}/${repo}/${pkgname}/${file}
  done

  if ! (set -o pipefail && generate-rospkg-apkbuild \
    ${repo} ${APORTSDIR}/${repo}/${pkgname}/package.xml --src \
      --ver-suffix=_git${commit_date} \
      | tee ${APORTSDIR}/${repo}/${pkgname}/APKBUILD); then
    echo "## Package dependency failure" >> ${summary_file}
    error=true
  fi
done

rm -f $(find ${APORTSDIR} -name "ros-abuild-build.log")
rm -f $(find ${APORTSDIR} -name "ros-abuild-check.log")
rm -f $(find ${APORTSDIR} -name "ros-abuild-status.log")


# Tweak version constraints

if [ "${FORCE_LOCAL_VERSION}" = "yes" ]; then
  echo "FORCE_LOCAL_VERSION: enabled"
  # Find all package versions
  apkbuilds="$(find ${APORTSDIR} -name "APKBUILD")"
  for apkbuild in ${apkbuilds}; do
    pkgname=$(. ${apkbuild}; echo "${pkgname}")
    pkgver=$(. ${apkbuild}; echo "${pkgver}")
    pkgrel=$(. ${apkbuild}; echo "${pkgrel}")

    # Specify package versions
    for apkbuild_subst in ${apkbuilds}; do
      sed \
        "/depends=/!b end; s/\([ \t\"']\)${pkgname}\([ \t\"']\)/\1${pkgname}=${pkgver}-r${pkgrel}\2/g; :end" \
        -i ${apkbuild_subst}
    done
  done

  echo
  echo "Tweaked APKBUILD dependencies:"
  grep -r "depends=" ${APORTSDIR}
  echo
fi


# Build everything

GENERATE_BUILD_LOGS=yes buildrepo -k -d ${REPODIR} -a ${APORTSDIR} ${repo} | tee ${full_log_file}


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

rm -f ${summary_file} ${apk_list_file}

echo "## Summary" >> ${summary_file}
echo '```' >> ${summary_file}
tail -n6 ${full_log_file} >> ${summary_file}
echo '```' >> ${summary_file}

for manifest in ${manifests}; do
  srcpath=$(dirname ${manifest})
  pkgname=$(basename ${srcpath})
  pkgpath=${APORTSDIR}/${repo}/${pkgname}

  apk_filename=$(. ${pkgpath}/APKBUILD; echo "${pkgname}-${pkgver}-r${pkgrel}.apk")

  echo >> ${summary_file}
  echo "## $pkgname" >> ${summary_file}
  echo "**${apk_filename}**" >> ${summary_file}
  echo "${apk_filename}" >> ${apk_list_file}

  if [ ! -f ${pkgpath}/${build_subdir}/ros-abuild-status.log ]; then
    if [ -f ${REPODIR}/${repo}/*/${apk_filename} ]; then
      echo "Already been built." >> ${summary_file}
    else
      echo "Failed to start build. The package might have unsatisfied dependencies." >> ${summary_file}
      error=true
    fi
    continue
  fi
  if grep "finished" ${pkgpath}/${build_subdir}/ros-abuild-status.log > /dev/null; then
    echo "Build succeeded." >> ${summary_file}
    if grep "Check skipped" ${pkgpath}/${build_subdir}/ros-abuild-check.log > /dev/null; then
      echo "(NOCHECK)" >> ${summary_file}
    fi
    if [ ! -f ${REPODIR}/${repo}/*/${apk_filename} ]; then
      echo "Failed to generate package." >> ${summary_file}
      error=true
    fi
    continue
  fi

  error=true

  echo "### Build log" >> ${summary_file}
  if [ ! -f ${pkgpath}/${build_subdir}/ros-abuild-build.log ]; then
    echo "Build log not found" >> ${summary_file}
    continue
  fi
  echo "\`\`\`" >> ${summary_file}
  summarize_error ${pkgpath}/${build_subdir}/ros-abuild-build.log "error" >> ${summary_file}
  echo "\`\`\`" >> ${summary_file}

  if [ -f ${pkgpath}/${build_subdir}/ros-abuild-check.log ]; then
    echo "### Check log" >> ${summary_file}
    echo '```' >> ${summary_file}
    summarize_error ${pkgpath}/${build_subdir}/ros-abuild-check.log "(error|failure)" >> ${summary_file}
    echo '```' >> ${summary_file}
    continue
  fi
done

echo
echo "---"
cat ${summary_file}

if [ $error != "false" ]; then
  exit 1
fi

exit 0
