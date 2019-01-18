#!/bin/sh

set -e

[ $# -lt 1 ] \
  && (echo "usage: $0 repository-name"; false)

arch=x86_64
version=`grep -e "alpine/.*/main" /etc/apk/repositories | sed -r "s/^.*\/alpine\/([^\
/]*)\/main$/\1/"`
REPODEST=$REPODEST/$version
echo "Running on Alpine $version"
echo

branch_option=
if [ ! -z $APORTS_BRANCH ]
then
  branch_option="-b $APORTS_BRANCH"
  echo "Using $APORTS_BRANCH branch of seqsense/aports-ros-experimental"
fi

cd /tmp
git clone --depth=1 -q $branch_option https://github.com/seqsense/aports-ros-experimental
cd aports-ros-experimental/$1

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
    apk info $dep > /dev/null \
      && (grep $dep /tmp/building > /dev/null && echo $dep >> /tmp/deps/$pkg || true) \
      || (echo $dep >> /tmp/deps/$pkg)
  done
  (source $pkg/APKBUILD && echo $depends_dev) | xargs -r -n1 echo | while read dep
  do
    dep=`echo $dep | sed -e "s/[><=]\{1,2\}[0-9.]*$//"`
    apk info $dep > /dev/null \
      && (grep $dep /tmp/building > /dev/null && echo $dep >> /tmp/deps/$pkg || true) \
      || (echo $dep >> /tmp/deps/$pkg)
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
      (ls -1 /tmp/deps/* 2> /dev/null || true) | xargs -r -n1 sed -e "/^$pkg\([><=]\{1,2\}[0-9.]*\)\{0,1\}$/d" -i
      while read sub
      do
        (ls -1 /tmp/deps/* 2> /dev/null || true) | xargs -r -n1 sed -e "/^$sub\([><=]\{1,2\}[0-9.]*\)\{0,1\}$/d" -i
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
  if [ `source $pkg/APKBUILD && echo $arch` == "noarch" ]
  then
    sed -e 's/arch="noarch"/arch="all"/' -i $pkg/APKBUILD
  fi
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
