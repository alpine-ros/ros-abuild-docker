#!/bin/sh

set -e

[ $# -lt 2 ] \
  && (echo "usage: $0 distro-name package-name"; false)

arch=x86_64
version=`grep -e "alpine/.*/main" /etc/apk/repositories | sed -r "s/^.*\/alpine\/([^\
/]*)\/main$/\1/"`
REPODEST=$REPODEST/$version/${REPOSITORY_NAME:-ros}
echo "Running on Alpine $version"
echo

ROS_DISTRO=$1

if [ -z ${PACKAGE_FROM_URI} ]
then
  if [ -z ${ROSDISTRO_INDEX_URL} ]
  then
    (cd /local_index; ./load.sh)
    export ROSDISTRO_INDEX_URL=file:///local_index/index.yaml
  fi
fi

rosdep update

/scripts/generate_ros_package_list.sh $1 ${@:2} | tee /tmp/ros_packages.list

echo "----------------"
echo "generating APKBUILD:"
mkdir -p /tmp/ros/$1
cd /tmp/ros/$1
rm -f /tmp/gen-apkbuild-failure
while read line
do
  pkg=`echo $line | cut -f1 -d' '`
  uri=`echo $line | cut -f2 -d' '`
  options=`echo $line | cut -f3- -d' '`
  mkdir -p $pkg
  echo "  - $pkg"
  if [ -z ${PACKAGE_FROM_URI} ]
  then
    /scripts/generate_apkbuild.py $ROS_DISTRO $pkg $options > $pkg/APKBUILD \
      || echo $pkg >> /tmp/gen-apkbuild-failure
  else
    /scripts/generate_apkbuild.py $ROS_DISTRO $uri $options > $pkg/APKBUILD \
      || echo $pkg >> /tmp/gen-apkbuild-failure
  fi
done < /tmp/ros_packages.list
if [ -f /tmp/gen-apkbuild-failure ]
then
  echo "Failed to generate APKBUILD for:"
  cat /tmp/gen-apkbuild-failure | sed "s/^/- /"
  exit 1
fi
echo "----------------"

ls -1 | while read pkg
do
  if [ -f $pkg/ENABLE_ON ]
  then
    grep $version $pkg/ENABLE_ON > /dev/null || continue
  fi
  echo $pkg
done > /tmp/building

echo "----------------"
echo "building:"
cat /tmp/building | sed "s/^/- /"
echo "----------------"

sudo apk update
sudo apk add py-rosdep py-rospkg py-wstool py-vcstools py-rosinstall-generator python2-dev python3-dev

echo "----------------"
echo "checking deps:"
rm -rf /tmp/deps
mkdir -p /tmp/deps
rm -rf /tmp/subs
mkdir -p /tmp/subs
cat /tmp/building | while read pkg
do
  touch /tmp/deps/$pkg
  touch /tmp/subs/$pkg
  (source $pkg/APKBUILD && echo $makedepends) | xargs -r -n1 echo | while read dep
  do
    dep=`echo $dep | sed -e "s/[><=]\{1,2\}[0-9.]*$//"`
    apk info $dep > /dev/null || echo $dep >> /tmp/deps/$pkg
  done
  (source $pkg/APKBUILD && echo $depends) | xargs -r -n1 echo | while read dep
  do
    dep=`echo $dep | sed -e "s/[><=]\{1,2\}[0-9.]*$//"`
    apk info $dep > /dev/null || echo $dep >> /tmp/deps/$pkg
  done
  (source $pkg/APKBUILD && echo $subpackages) | xargs -r -n1 echo | while read sub
  do
    echo $sub | cut -f1 -d":" >> /tmp/subs/$pkg
  done
  echo "  $pkg requires:"
  cat /tmp/deps/$pkg | sed "s/^/  - /"
done
echo "----------------"

echo "----------------"
echo "subpackages:"
cat /tmp/building | while read pkg
do
  echo "  $pkg contains:"
  cat /tmp/subs/$pkg | sed "s/^/  - /"
done
echo "----------------"

echo "----------------"
echo "generating build tree:"
rm -f /tmp/building2
touch /tmp/building2
while true
do
  nremain=`cat /tmp/building | sed '/^\s*$/d' | wc -l`
  if [ $nremain -eq 0 ]
  then
    break
  fi

  newresolve=false
  while read pkg
  do
    ndep=`cat /tmp/deps/$pkg | sed '/^\s*$/d' | wc -l`
    if [ $ndep -eq 0 ]
    then
      echo "- $pkg"
      echo $pkg >> /tmp/building2
      newresolve=true
      rm /tmp/deps/$pkg
      rospkg=ros-$1-`echo $pkg | sed 's/_/-/g'`
      (ls -1 /tmp/deps/* 2> /dev/null || true) | xargs -r -n1 sed -e "/^$pkg$/d" -i
      (ls -1 /tmp/deps/* 2> /dev/null || true) | xargs -r -n1 sed -e "/^$rospkg$/d" -i
      while read sub
      do
        rossub=ros-$1-`echo $sub | sed 's/_/-/g'`
        (ls -1 /tmp/deps/* 2> /dev/null || true) | xargs -r -n1 sed -e "/^$sub$/d" -i
        (ls -1 /tmp/deps/* 2> /dev/null || true) | xargs -r -n1 sed -e "/^$rossub$/d" -i
      done < /tmp/subs/$pkg
      sed -e "/^$pkg$/d" -i /tmp/building
    fi
  done < /tmp/building

  if [ $newresolve == "false" ]
  then
    echo "Failed to resolve dependency tree for:"
    cat /tmp/building | while read pkg
    do
      echo $pkg | sed "s/^/- /"
      cat /tmp/deps/$pkg | sed "s/^/  - /"
    done
    exit 1
  fi
done
echo "----------------"

cat /tmp/building2 | while read pkg
do
  echo "----------------"
  exist=true
  (cd $pkg && abuild listpkg > /tmp/$pkg-deps)
  while read apkname
  do
    echo "Checking $apkname"
    if [ ! -f $REPODEST/$1/$arch/$apkname ]
    then
      echo "  - $REPODEST/$1/$arch/$apkname does not exist"
      exist=false
    fi
  done < /tmp/$pkg-deps
  if [ $exist == "true" ]
  then
    echo "$pkg is up-to-date"
    continue
  fi

  (cd $pkg \
    && abuild checksum \
    && abuild -r) || (echo "====== Failed to build $pkg ====="; false)
done

echo "----------------"
echo "regenerating index:"

rm -f $REPODEST/$1/$arch/APKINDEX.tar.gz
apk index -o $REPODEST/$1/$arch/APKINDEX.tar.gz `find $REPODEST/$1/$arch -name '*.apk'`
abuild-sign -k /home/builder/.abuild/*.rsa $REPODEST/$1/$arch/APKINDEX.tar.gz
