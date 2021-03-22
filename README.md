# ros-abuild-docker

Alpine Linux package builder for ROS (Robot Operating System)

## Build builder container

```shell
docker pull ghcr.io/alpine-ros/ros-abuild:3.11-noetic
```
or build locally

```shell
docker build -t ghcr.io/alpine-ros/ros-abuild:3.11-noetic .
```

## Build ROS package(s)

### Just build and test

```shell
docker run -it --rm \
  -v $(pwd):/src:ro \
  ghcr.io/alpine-ros/ros-abuild:3.11-noetic
```

If `*.rosinstall` file is present, packages specified in the file will be automatically cloned and built.

### Get generated apk packages

Create a directory to store packages.
```shell
mkdir -p /path/to/your/packages
```

Build and output generated packages to the directory.
```shell
docker run -it --rm \
  -v $(pwd):/src:ro \
  -v /path/to/your/packages:/packages
  ghcr.io/alpine-ros/ros-abuild:3.11-noetic
```

### Build with cache

Create docker volume to store Alpine package cache and rosdep cache.
```shell
docker volume create ros-abuild-apk
docker volume create ros-abuild-rosdep
```

Build with cache.
```shell
mkdir -p /path/to/your/packages  # Create a directory to store packages.
docker run -it --rm \
  -v $(pwd):/src:ro \
  -v ros-abuild-apk:/var/cache/apk \
  -v ros-abuild-rosdep:/home/builder/.ros/rosdep \
  -e SKIP_ROSDEP_UPDATE=true \
  ghcr.io/alpine-ros/ros-abuild:3.11-noetic
```
