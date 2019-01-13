#!/bin/sh

wget http://repositories.ros.org/rosdistro_cache/indigo-cache.yaml.gz
wget http://repositories.ros.org/rosdistro_cache/kinetic-cache.yaml.gz
wget http://repositories.ros.org/rosdistro_cache/lunar-cache.yaml.gz
wget http://repositories.ros.org/rosdistro_cache/melodic-cache.yaml.gz

gunzip *.gz

for d in indigo kinetic lunar melodic
do
  echo $d
  mkdir -p $d
  wget -P $d https://raw.githubusercontent.com/ros/rosdistro/master/$d/distribution.yaml
done
