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
@[if split_dev]@
depends_dev="@(' '.join(depends_dev))"

subpackages="$pkgname-dbg $pkgname-doc $pkgname-dev"
@[else]@

subpackages="$pkgname-dbg $pkgname-doc"
@[end if]@

source=""
builddir="$startdir/abuild"
srcdir="/tmp/dummy-src-dir"
buildlog="$builddir/ros-abuild-build.log"
checklog="$builddir/ros-abuild-check.log"
statuslog="$builddir/ros-abuild-status.log"
if [ x${GENERATE_BUILD_LOGS} != "xyes" ]; then
  buildlog="/dev/null"
  checklog="/dev/null"
  statuslog="/dev/null"
fi

@[if not is_ros2]@
export ROS_PACKAGE_PATH="$builddir/src/$_pkgname"
@[end if]@
export ROS_PYTHON_VERSION=@ros_python_version
@[if is_ros2]@
export PYTHON_VERSION=$(python3 -c 'import sys; print("%i.%i" % (sys.version_info.major, sys.version_info.minor))')
if [ ! -f /usr/ros/@(ros_distro)/setup.sh ]; then
  export PYTHONPATH=/usr/ros/@(ros_distro)/lib/python${PYTHON_VERSION}/site-packages:$PYTHONPATH
  export AMENT_PREFIX_PATH=/usr/ros/@(ros_distro)
fi
@[end if]@
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
  vcs import @vcstool_opt --input pkg.rosinstall src
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
@[  if ros_python_version == '3']@
  # Overwrite shebang
  find src -type f | while read file; do
    h=$(head -n1 "$file")
    rewrite_shebang=false
    if echo $h | grep -q -s "^#!\s*/usr/bin/env\s*python$"; then
      rewrite_shebang=true
    fi
    if echo $h | grep -q -s "^#!\s*/usr/bin/python$"; then
      rewrite_shebang=true
    fi
    if [ $rewrite_shebang == "true" ]; then
      echo "WARN: rewriting python shebang of $file"
      sed -i "1c#\!/usr/bin/env python3" "$file"
    fi
  done
@[  end if]@
  source /usr/ros/@(ros_distro)/setup.sh
  catkin_make_isolated \
@[for cmake_arg in cmake_args]@
    @(cmake_arg) \
@[end for]@
    -DCMAKE_BUILD_TYPE=RelWithDebInfo 2>&1 | tee $buildlog
@[end if]@
@[if is_ros2]@
  if [ -f /usr/ros/@(ros_distro)/setup.sh ]; then
    source /usr/ros/@(ros_distro)/setup.sh
  fi
@[end if]@
@[if use_cmake or use_ament_cmake]@
  mkdir build
  cd build
  cmake ../src/$_pkgname \
@[for cmake_arg in cmake_args]@
    @(cmake_arg) \
@[end for]@
    -DCMAKE_INSTALL_PREFIX=/usr/ros/@(ros_distro) \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_LIBDIR=lib 2>&1 | tee $buildlog
  make 2>&1 | tee -a $buildlog
@[end if]@
@[if use_ament_python]@
  # Directory to place intermediate files
  mkdir -p "$builddir"/tmp
  cd src/$_pkgname
  python setup.py egg_info --egg-base="$builddir"/tmp 2>&1 | tee $buildlog
  python setup.py \
    build \
    --build-base="$builddir"/tmp/build
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

  if [ -z "$ROS_LOG_DIR" ]; then
    logdir="$builddir/log"
    mkdir -p "$logdir"
    export ROS_LOG_DIR="$logdir"
  fi

  source /usr/ros/@(ros_distro)/setup.sh
  source devel_isolated/setup.sh
  catkin_make_isolated \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    --catkin-make-args run_tests 2>&1 | tee $checklog
  catkin_test_results 2>&1 | tee $checklog
@[  end if]@
@[  if is_ros2]@
  if [ -f /usr/ros/@(ros_distro)/setup.sh ]; then
    source /usr/ros/@(ros_distro)/setup.sh
  fi
@[  end if]@
@[  if use_ament_cmake or use_ament_python]@
  export PYTHONPATH="$builddir"/tmp/pkg/usr/ros/@(ros_distro)/lib/python${PYTHON_VERSION}/site-packages:${PYTHONPATH}
  export AMENT_PREFIX_PATH="$builddir"/tmp/pkg/usr/ros/@(ros_distro):${AMENT_PREFIX_PATH}
  export PATH="$builddir"/tmp/pkg/usr/ros/@(ros_distro)/bin:${PATH}
  export LD_LIBRARY_PATH="$builddir"/tmp/pkg/usr/ros/@(ros_distro)/lib:${LD_LIBRARY_PATH}
  mkdir -p "$builddir"/tmp/pkg
@[  end if]@
@[  if use_cmake or use_ament_cmake]@
  cd build
@[  if use_ament_cmake]@
  make install DESTDIR="$builddir"/tmp/pkg
@[  end if]@
  if [ $(make -q test > /dev/null 2> /dev/null; echo $?) -eq 1 ]; then
    make test 2>&1 | tee $checklog
  fi
@[  end if]@
@[  if use_ament_python]@
  cd src/$_pkgname
  python setup.py \
    build \
    --build-base="$builddir"/tmp/build \
    install \
    --root="$builddir"/tmp/pkg \
    --prefix=/usr/ros/@(ros_distro) 2>&1 | tee $buildlog
  TEST_TARGET=$(ls -d */ | grep -m1 "\(test\|tests\)") || true
  if [ -z "$TEST_TARGET" ]; then
    echo "No \"test\" or \"tests\" directory. Check skipped" | tee $checklog
    return 0
  fi
  USE_PYTEST=$(grep '\<pytest\>' setup.py) || true
  if [ -n "$USE_PYTEST" ]; then
    python -m pytest 2>&1 | tee $checklog
  else
    python setup.py test 2>&1 | tee $checklog
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
@[if not use_ament_python]@
  export DESTDIR="$pkgdir"
@[end if]@

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
@[if is_ros2]@
  if [ -f /usr/ros/@(ros_distro)/setup.sh ]; then
    source /usr/ros/@(ros_distro)/setup.sh
  fi
@[end if]@
@[if use_cmake or use_ament_cmake]@
  cd build
  make install
@[end if]@
@[if use_ament_python]@
  cd src/$_pkgname
  python setup.py \
    build \
    --build-base="$builddir"/tmp/build \
    install \
    --root="$pkgdir" \
    --prefix=/usr/ros/@(ros_distro)
@[end if]@

  # Tweak invalid RPATH
  find $pkgdir -name "*.so" | while read so; do
    chrpath_out=$(chrpath ${so} || true)
    if echo ${chrpath_out} | grep -q "R\(UN\)\?PATH="; then
      rpath=$(echo -n "${chrpath_out}" | sed -e "s/^.*R\(UN\)\?PATH=//")
      if echo "${rpath}" | grep -q -e "\(home\|aports\)"; then
        echo "RPATH contains home/aports!: ${rpath}"
        rpathfix=$(echo -n "${rpath}" | tr ":" "\n" \
          | grep -v -e home | grep -v -e aports \
          | tr "\n" ":" | sed -e "s/:$//; s/::/:/;")
        echo "Fixing to ${rpathfix}"
        chrpath -r ${rpathfix} ${so} || (echo chrpath failed; false)
      fi
    fi
  done

  # Tweak hardcoded library versions
  find $pkgdir -name "*.cmake" | while read cm; do
    libs=$(sed -n '/^set(libraries/{s/^.*"\(.*\)")$/\1/;s/;/ /g;p}' $cm)
    for lib in $libs; do
      rep=
      # lib.so.0.1.2 -> lib.so.0.1
      if echo $lib | grep -q -e '\.so\.[0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}$'; then
        rep=$(echo $lib | sed -e 's/\(\.so\.[0-9]\{1,\}\.[0-9]\{1,\}\)\.[0-9]\{1,\}$/\1/')
      fi
      # lib-0.1.so.2 -> lib-0.1.so
      if echo $lib | grep -q -e '-[0-9]\{1,\}\.[0-9]\{1,\}\.so\.[0-9]\{1,\}$'; then
        rep=$(echo $lib | sed -e 's/\(-[0-9]\{1,\}\.[0-9]\{1,\}\.so\)\.[0-9]\{1,\}$/\1/')
      fi

      if [ ! -z "$rep" ]; then
        if [ -f $rep ]; then
          echo "$cm: $lib -> $rep"
          sed -e "s|\([\";]\)$lib\([\";]\)|\1$rep\2|g" -i $cm
        else
          echo "$cm: $lib is specified, but $rep doesn't exist"
        fi
      fi
    done
  done

  # Install license files
  licensedir="$pkgdir"/usr/share/licenses/$pkgname/
  cd $builddir/src/$_pkgname
  find . \
      -iname "license*" -or \
      -iname "copyright*" -or \
      -iname "copying*" -or \
      -iname "gnu-*gpl*" \
    | while read file; do
    # Copy license files under the source
    if echo $file | grep -e '^\./\.'; then
      # Omit files under hidden directory
      continue
    fi
@[if use_cmake or use_ament_cmake]@
    if echo $file | grep -e '^\./build/'; then
      # Omit files under build directory
      continue
    fi
@[end if]@
    echo "Copying license files from source tree: $file"
    install -Dm644 $file "$licensedir"/$file
  done
  if [ -f $startdir/LICENSE ]; then
    # If LICENSE file is in aports directory, copy it
    echo "Copying license file from aports"
    install -Dm644 $startdir/LICENSE "$licensedir"/LICENSE
  fi
  if [ -f $startdir/LICENSE_URLS ]; then
    # If LICENSE_URLS file is in aports directory, download it
    echo "Downloading license file from URLs"
    cat $startdir/LICENSE_URLS | while read url; do
      echo "- $url"
      mkdir -p "$licensedir"
      wget -O "$licensedir"/$(basename $url) $url
    done
  fi
  if [ -z "$(find "$licensedir" -type f)" ]; then
    # If no explicit license file found, extract from source files
    mkdir -p "$licensedir"
    echo "Copying license from source file headers"
    find . -name "*.h" -or -name "*.c" -or -name "*.cpp" -or -name "*.py" | while read file; do
      echo "Checking license header in $file"
      tmplicense=$(mktemp)
      # Extract heading comment
      sed -n '1{/^#!/d};
        /\/\*/{/\*\//d; :l0; p; n; /\*\//!b l0; p; q};
        /^\s*#/{:l1; /^#!/!p; n; /^\s*#/b l1; q};
        /^\s*\/\//{:l2; p; n; /^\s*\/\//b l2; q};' $file > $tmplicense
      # Remove comment syntax
      sed 's/\/\*//; s/\*\///; s/^s*\/\/\s\{0,1\}//;
        s/^ \* \{0,1\}//; s/^\s*# \{0,1\}//; s/\s\+$//;' -i $tmplicense
      # Trim empty lines
      sed ':l0; /^$/d; n; /^$/!b l0; :l1; n; b l1;' -i $tmplicense
      sed '${/^$/d}' -i $tmplicense

      if ! grep -i -e "\(license\|copyright\|copyleft\)" $tmplicense > /dev/null; then
        # Looks not like a license statement
        echo "No license statement"
        rm -f $tmplicense
        continue
      fi

      echo "Checking duplication"
      licenses=$(mktemp)
      find "$licensedir" -type f > $licenses
      savethis=true
      while read existing; do
        if diff -bBiw $tmplicense $existing > /dev/null; then
          # Same license statement found
          savethis=false
          break
        fi
      done < $licenses

      if $savethis; then
        # Save license statement
        local num=0
        while true; do
          newfile="$licensedir"/LICENSE.$num
          if [ ! -f "$newfile" ]; then
            echo "Saving license statement as $newfile"
            mv $tmplicense $newfile
            break
          fi
          num=$(expr $num + 1)
        done
      fi

      rm -f $licenses $tmplicense
    done
  fi
  # List license files
  echo "License files:"
  find "$licensedir" -type f | xargs -n1 echo "-"

  echo "finished" >> $statuslog
}

doc() {
  mkdir -p $subpkgdir

  default_doc
}
@[if split_dev]@

dev() {
  local i=
  mkdir -p $subpkgdir

  install_if="${subpkgname%-dev}=$pkgver-r$pkgrel ros-dev"
	depends="$depends_dev"
	pkgdesc="$pkgdesc (development files)"

  cd $pkgdir || return 0

  for i in \
    usr/ros/*/lib/pkgconfig \
    usr/ros/*/share/*/cmake \
    usr/ros/*/include \
    $(find usr/ros/*/lib -name -name '*.[choa]' -o -name '*.prl' 2>/dev/null); do
    if [ -e "$i" ] || [ -L "$i" ]; then
      amove "$i"
    fi
  done
}
@[end if]
if [ -f ./apkbuild_hook.sh ]; then
  . ./apkbuild_hook.sh
  apkbuild_hook
fi
