# ros-abuild-docker

Spike implementation of Alpine Linux package builder for ROS (Robot Operating System)

## generate rsa key

```shell
openssl genrsa --out test.rsa 2048
openssl rsa -in test.rsa -pubout -out test.rsa.pub
```

## build backport packages

Package definitions are in https://github.com/seqsense/aports-ros-experimental

```shell
docker run \
  -v "`pwd`/test.rsa:/home/builder/.abuild/builder@alpine-ros-experimental.rsa:ro" \
  -v "`pwd`/test.rsa.pub:/etc/apk/keys/builder@alpine-ros-experimental.rsa.pub:ro" \
  -v "`pwd`/packages:/packages" \
  --rm -it abuild-docker /all.sh backports
```
