#!/bin/sh

set -e

/scripts/build.sh backports
/scripts/ros.sh
