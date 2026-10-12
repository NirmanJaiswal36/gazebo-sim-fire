#!/usr/bin/env bash
# `docker compose exec` bypasses this; interactive shells get the same
# environment from ~/.bashrc.
set -e
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
exec "$@"
