# ros-abuild-docker

Alpine Linux package builder for ROS (Robot Operating System)

## Build builder container

```shell
docker build -t alpineros/ros-abuild:3.7-kinetic .
```

or pull from docker hub

```shell
docker pull alpineros/ros-abuild:3.7-kinetic
```

## Build ROS package(s)

In ROS package directory:
```shell
docker run -it --rm \
  -v $(pwd):/src/$(basename $(pwd)):ro \
  -v /tmp:/logdir -e LOGDIR=/logdir \
  alpineros/ros-abuild:3.7-kinetic
```

In ROS meta-package root directory:
```shell
docker run -it --rm \
  -v $(pwd):/src:ro \
  -v /tmp:/logdir -e LOGDIR=/logdir \
  alpineros/ros-abuild:3.7-kinetic
```

If `*.rosinstall` file is present, packages specified in the file will be automatically cloned and built.
