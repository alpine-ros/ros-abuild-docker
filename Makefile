.PHONY: all dockerfiles
all:
 
dockerfiles: .dockerhub/kinetic.Dockerfile .dockerhub/melodic.Dockerfile .dockerhub/noetic.Dockerfile

.dockerhub/kinetic.Dockerfile: Dockerfile Makefile
	cp $< $@
	sed 's/\$${ALPINE_VERSION}/3.7/g' -i $@
	sed 's/\$${ROS_DISTRO}/kinetic/g' -i $@
	sed '/^ARG ALPINE_VERSION/d;/^ARG ROS_DISTRO/d;' -i $@
 
.dockerhub/melodic.Dockerfile: Dockerfile Makefile
	cp $< $@
	sed 's/\$${ALPINE_VERSION}/3.8/g' -i $@
	sed 's/\$${ROS_DISTRO}/melodic/g' -i $@
	sed '/^ARG ALPINE_VERSION/d;/^ARG ROS_DISTRO/d;' -i $@
 
.dockerhub/noetic.Dockerfile: Dockerfile Makefile
	cp $< $@
	sed 's/\$${ALPINE_VERSION}/3.11/g' -i $@
	sed 's/\$${ROS_DISTRO}/noetic/g' -i $@
	sed '/^ARG ALPINE_VERSION/d;/^ARG ROS_DISTRO/d;' -i $@
