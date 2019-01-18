#!/bin/sh

set -e

[ $# -lt 2 ] \
  && (echo "usage: $0 distro-name package-name"; false)

rosinstall_generator --flat --deps --rosdistro $1 ${@:2} | sed '1d' > /tmp/rosinstall
echo "- git:" >> /tmp/rosinstall

while read line
do
  echo $line | grep -e "^\s*local-name:" > /dev/null \
    && name=`echo $line | sed "s/^\s*local-name:\s*//"`
  echo $line | grep -e "^\s*uri:" > /dev/null \
    && uri=`echo $line | sed "s/^\s*uri:\s*//" | sed "s/github\.com/raw.githubusercontent.com/" | sed "s/\.git$//"`
  echo $line | grep -e "^\s*version:" > /dev/null \
    && version=`echo $line | sed "s/^\s*version:\s*//"`

  echo $line | grep -e "^- git:" > /dev/null \
    && ( nocheck=; \
         grep -e "^$name$" ros_nocheck.list > /dev/null && nocheck=--nocheck; \
         echo $name $uri/$version/package.xml $nocheck )
done < /tmp/rosinstall
