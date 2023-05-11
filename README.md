# ros-abuild-docker

Alpine Linux package builder for ROS (Robot Operating System)

## Build builder container

```shell
docker pull ghcr.io/alpine-ros/ros-abuild:3.14-noetic
```

or build locally

```shell
docker build \
  --build-arg ROS_DISTRO=noetic \
  --build-arg ALPINE_VERSION=3.14 \
  --build-arg ROS_PYTHON_VERSION=3 \
  -t ghcr.io/alpine-ros/ros-abuild:3.14-noetic .
```

## Build ROS package(s)

### Just build and test

Run following command at the root of the ROS package repository:
```shell
docker run -it --rm \
  -v $(pwd):/src:ro \
  ghcr.io/alpine-ros/ros-abuild:3.14-noetic
```
(`$(pwd)` can be replaced by a full path to the ROS package repository.)

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
  -v /path/to/your/packages:/packages \
  ghcr.io/alpine-ros/ros-abuild:3.14-noetic
```

### Build with cache

Create docker volume to store Alpine package cache, rosdep cache and gcc build cache.
```shell
docker volume create ros-abuild-apk
docker volume create ros-abuild-rosdep
docker volume create ros-abuild-ccache
```

Build with cache.
```shell
mkdir -p /path/to/your/packages  # Create a directory to store packages.
docker run -it --rm \
  -v $(pwd):/src:ro \
  -v ros-abuild-apk:/var/cache/apk \
  -v ros-abuild-rosdep:/home/builder/.ros/rosdep \
  -v ros-abuild-ccache:/ccache \
  -e SKIP_ROSDEP_UPDATE=yes \
  -e ENABLE_CCACHE=yes \
  ghcr.io/alpine-ros/ros-abuild:3.14-noetic
```
