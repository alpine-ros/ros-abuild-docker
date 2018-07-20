# abuild-docker

## generate rsa key

```shell
openssl genrsa --out test.rsa 2048
openssl rsa -in test.rsa -pubout -out test.rsa.pub
```

## run abuild commands

```shell
docker run -v "`pwd`/test.rsa:/home/builder/.abuild/builder@alpine-ros-experimental.rsa:ro" -v "`pwd`/test.rsa.pub:/etc/apk/keys/builder@alpine-ros-experimental.rsa.pub:ro" -v "`pwd`/packages:/packages" --rm -it abuild-docker COMMANDS
```
