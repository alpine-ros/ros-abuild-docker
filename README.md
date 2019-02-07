# ros-abuild-docker

Alpine Linux package builder for ROS (Robot Operating System)

## Build builder container

```shell
docker build -t ros-abuild .
```

## Build ROS package(s)

In ROS package directory:
```shell
docker run -it --rm \
  -v `pwd`:/src/PACKAGE_NAME:ro \
  -v /tmp:/logdir -e LOGDIR=/logdir \
  ros-abuild
```

In ROS meta-package root directory:
```shell
docker run -it --rm \
  -v `pwd`:/src:ro \
  -v /tmp:/logdir -e LOGDIR=/logdir \
  ros-abuild
```

If `*.rosinstall` file is present, packages specified in the file will be automatically cloned and built.
