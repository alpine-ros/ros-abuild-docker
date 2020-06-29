.PHONY: all dockerfiles
all:
 
dockerfiles: .dockerhub/kinetic.Dockerfile .dockerhub/melodic.Dockerfile .dockerhub/noetic.Dockerfile

.dockerhub/kinetic.Dockerfile: Dockerfile Makefile
	cp $< $@
	sed 's/\$${ALPINE_VERSION}/3.7/g' -i $@
	sed 's/\$${ROS_DISTRO}/kinetic/g' -i $@
	sed 's/\$${ROS_PYTHON_VERSION}/2/g' -i $@
	sed '/^ARG \(ALPINE_VERSION\|ROS_\(DISTRO\|PYTHON_VERSION\)\)/d;' -i $@
	sed '1i # AUTOMATICALLY GENERATED: DO NOT EDIT THIS FILE BY HAND' -i $@
 
.dockerhub/melodic.Dockerfile: Dockerfile Makefile
	cp $< $@
	sed 's/\$${ALPINE_VERSION}/3.8/g' -i $@
	sed 's/\$${ROS_DISTRO}/melodic/g' -i $@
	sed 's/\$${ROS_PYTHON_VERSION}/2/g' -i $@
	sed '/^ARG \(ALPINE_VERSION\|ROS_\(DISTRO\|PYTHON_VERSION\)\)/d;' -i $@
	sed '1i # AUTOMATICALLY GENERATED: DO NOT EDIT THIS FILE BY HAND' -i $@
 
.dockerhub/noetic.Dockerfile: Dockerfile Makefile
	cp $< $@
	sed 's/\$${ALPINE_VERSION}/3.11/g' -i $@
	sed 's/\$${ROS_DISTRO}/noetic/g' -i $@
	sed 's/\$${ROS_PYTHON_VERSION}/3/g' -i $@
	sed '/^ARG \(ALPINE_VERSION\|ROS_\(DISTRO\|PYTHON_VERSION\)\)/d;' -i $@
	sed '1i # AUTOMATICALLY GENERATED: DO NOT EDIT THIS FILE BY HAND' -i $@