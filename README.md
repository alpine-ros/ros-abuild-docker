# abuild-docker

## generate rsa key

```shell
openssl genrsa --out test.rsa 2048
openssl rsa -in test.rsa -pubout -out test.rsa.pub
```

## run abuild commands

```shell
docker run -v "`pwd`/test.rsa:/home/builder/.abuild/builder.rsa:ro" -v "`pwd`/test.rsa.pub:/etc/apk/keys/builder.rsa.pub:ro" --rm -it abuild-docker COMMANDS
```
