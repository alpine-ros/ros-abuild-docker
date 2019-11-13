pkgname=@pkgname
_pkgname=@_pkgname
pkgver=@pkgver
pkgrel=@pkgrel
pkgdesc="$_pkgname package for ROS @ros_distro"
url="@url"
arch="all"
license="@license"
@[if not check]@
options="!check"
@[end if]@

depends="@(' '.join(depends))"
makedepends="@(' '.join(makedepends))"

subpackages="$pkgname-dbg"

source=""
builddir="$startdir/apk-build-temporary"
srcdir="/tmp/dummy-src-dir"
buildlog="$builddir/ros-abuild-build.log"
checklog="$builddir/ros-abuild-check.log"
statuslog="$builddir/ros-abuild-status.log"
if [ x${GENERATE_BUILD_LOGS} != "xyes" ]; then
  buildlog="/dev/null"
  checklog="/dev/null"
  statuslog="/dev/null"
fi

ROS_PYTHON_VERSION=@ros_python_version
@[if rosinstall is not None]@
rosinstall="@rosinstall"
@[end if]@

prepare() {
  set -o pipefail
  mkdir -p $builddir
  echo "preparing" > $statuslog
  cd "$builddir"
  rm -rf src || true
  mkdir -p src
@[if rosinstall is None]@
  cp -r $startdir src/$_pkgname || true  # ignore recursion error
@[else]@
  echo "$rosinstall" > pkg.rosinstall
  wstool init @wstool_opt src pkg.rosinstall
@[  if use_upstream]@
  find src -name package.xml | while read manifest; do
    dir=$(dirname $manifest)
    pkg=$(sed $manifest \
          -e ':l1;N;$!b l1;s/.*<\s*name\s*>\s*\(.*\)\s*<\s*\/name\s*>.*/\1/;')
    if [ $pkg != $_pkgname ]; then
      echo Ignoring $pkg which is not $_pkgname
      touch $dir/CATKIN_IGNORE
    fi
  done
@[  end if]@
@[end if]@
  find $startdir -maxdepth 1 -name "*.patch" | while read patchfile; do
    echo "Applying $patchfile"
    (cd src/* && patch -p1 -i $patchfile)
  done
}

build() {
  set -o pipefail
  echo "building" > $statuslog
  cd "$builddir"
@[if use_catkin]@
  source /usr/ros/@(ros_distro)/setup.sh
  catkin_make_isolated \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo 2>&1 | tee $buildlog
@[end if]@
@[if use_cmake]@
  mkdir src/$_pkgname/build
  cd src/$_pkgname/build
  cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr/ros/@(ros_distro) \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_LIBDIR=lib 2>&1 | tee $buildlog
  make 2>&1 | tee -a $buildlog
@[end if]@
}

@[if check]@
check() {
  if [ -f $startdir/NOCHECK ]; then
    echo "Check skipped" | tee $checklog
    return 0
  fi
  set -o pipefail
  echo "checking" >> $statuslog
  cd "$builddir"
@[  if use_catkin]@
  source /usr/ros/@(ros_distro)/setup.sh
  source devel_isolated/setup.sh
  catkin_make_isolated \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    --catkin-make-args run_tests 2>&1 | tee $checklog
  catkin_test_results 2>&1 | tee $checklog
@[  end if]@
@[  if use_cmake]@
  cd src/$_pkgname/build
  if [ $(make -q test > /dev/null 2> /dev/null; echo $?) -eq 1 ]; then
    make test 2>&1 | tee $checklog
  fi
@[  end if]@
}
@[end if]@

dbg() {
  mkdir -p "$subpkgdir"
  default_dbg
}

package() {
  echo "packaging" >> $statuslog
  mkdir -p "$pkgdir"
  cd "$builddir"
  export DESTDIR="$pkgdir"

@[if use_catkin]@
  source /usr/ros/@(ros_distro)/setup.sh
  catkin_make_isolated \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    --install-space /usr/ros/@(ros_distro)
  catkin_make_isolated \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    --install --install-space /usr/ros/@(ros_distro)
  rm -f \
    "$pkgdir"/usr/ros/@(ros_distro)/setup.* \
    "$pkgdir"/usr/ros/@(ros_distro)/local_setup.* \
    "$pkgdir"/usr/ros/@(ros_distro)/.rosinstall \
    "$pkgdir"/usr/ros/@(ros_distro)/_setup_util.py \
    "$pkgdir"/usr/ros/@(ros_distro)/env.sh \
    "$pkgdir"/usr/ros/@(ros_distro)/.catkin
@[end if]@
@[if use_cmake]@
  cd src/$_pkgname/build
  make install
@[end if]@

  find $pkgdir -name "*.so" | while read so; do
    chrpath_out=$(chrpath ${so} || true)
    if echo ${chrpath_out} | grep -q "RPATH="; then
      rpath=$(echo -n "${chrpath_out}" | sed -e "s/^.*RPATH=//")
      if echo "${rpath}" | grep -q home; then
        echo "RPATH contains home!: ${rpath}"
        rpathfix=$(echo -n "${rpath}" | tr ":" "\n" \
          | grep -v -e home | tr "\n" ":" | sed -e "s/:$//; s/::/:/;")
        echo "Fixing to ${rpathfix}"
        chrpath -r ${rpathfix} ${so} || (echo chrpath failed; false)
      fi
    fi
  done

  echo "finished" >> $statuslog
}