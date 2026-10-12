# ArduPilot SITL + Gazebo Harmonic + ROS 2 Humble, for the forest swarm.
#
# Build from the repo root (see docker/README.md):
#     HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose build

FROM ros:humble-ros-base-jammy

ARG DEBIAN_FRONTEND=noninteractive
ARG HOST_UID=1000
ARG HOST_GID=1000
# Same commit the environment was developed against (ArduPilot master).
ARG ARDUPILOT_REF=995dc62b29f92096edac1ed74ef5473214d4950c

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# Gazebo Harmonic + ros_gz (Humble/Harmonic pairing comes from the OSRF repo)
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl gnupg lsb-release ca-certificates \
    && curl -fsSL https://packages.osrfoundation.org/gazebo.gpg \
        -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/gazebo-stable.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        gz-harmonic \
        ros-humble-ros-gzharmonic \
        ros-humble-cv-bridge \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Plugin build deps (.github/workflows/ubuntu-build.yml), ArduPilot SITL build
# deps, and the tools scripts/*.sh use (tmux, screen, ss).
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake make g++ ccache git sudo \
        rapidjson-dev libopencv-dev libunwind-dev \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl \
        python3-dev python3-pip python3-lxml python3-numpy \
        python3-opencv python3-matplotlib python3-wxgtk4.0 \
        libxml2-dev libxslt1-dev gawk \
        tmux screen iproute2 procps less nano \
        mesa-utils \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir \
        empy==3.3.4 pexpect future dronecan pyserial \
        pymavlink==2.4.49 MAVProxy==1.8.74

# ---------------------------------------------------------------------------
# Non-root user matching the host UID/GID, so X11 and the bind mounts work.
# -o tolerates the IDs already being taken in the base image.
# ---------------------------------------------------------------------------
RUN groupadd -o -g "${HOST_GID}" sim \
    && useradd -o -m -s /bin/bash -u "${HOST_UID}" -g "${HOST_GID}" \
        -G video,dialout sim \
    && echo "sim ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sim \
    && chmod 0440 /etc/sudoers.d/sim

USER sim
ENV HOME=/home/sim
WORKDIR /home/sim

# ---------------------------------------------------------------------------
# ArduPilot SITL. The tree is kept (owned by sim) because sim_vehicle.py runs
# waf on every launch; with copter already built that is a no-op.
# ---------------------------------------------------------------------------
RUN git init -q ardupilot \
    && cd ardupilot \
    && git remote add origin https://github.com/ArduPilot/ardupilot.git \
    && git fetch -q --depth 1 origin "${ARDUPILOT_REF}" \
    && git checkout -q FETCH_HEAD \
    && git submodule update --init --recursive --depth 1 \
    && ./waf configure --board sitl \
    && ./waf copter

ENV PATH=/home/sim/ardupilot/Tools/autotest:${PATH}

# ---------------------------------------------------------------------------
# Pre-fetch the Fuel trees worlds/forest.sdf includes, so it loads offline.
# ---------------------------------------------------------------------------
RUN gz fuel download -v 3 -u "https://fuel.gazebosim.org/1.0/OpenRobotics/models/Oak Tree" \
    && gz fuel download -v 3 -u "https://fuel.gazebosim.org/1.0/OpenRobotics/models/Pine Tree"

# ---------------------------------------------------------------------------
# ardupilot_gazebo plugin + generated swarm models
# ---------------------------------------------------------------------------
COPY --chown=sim:sim . /home/sim/ardupilot_gazebo
WORKDIR /home/sim/ardupilot_gazebo

RUN mkdir -p build && cd build \
    && cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    && make -j"$(nproc)" \
    && cd .. \
    && python3 tools/gen_swarm.py -n 8

ENV GZ_VERSION=harmonic \
    GZ_SIM_RESOURCE_PATH=/home/sim/ardupilot_gazebo/models:/home/sim/ardupilot_gazebo/worlds \
    GZ_SIM_SYSTEM_PLUGIN_PATH=/home/sim/ardupilot_gazebo/build \
    ROS_DOMAIN_ID=121

RUN echo "source /opt/ros/humble/setup.bash" >> /home/sim/.bashrc \
    && echo "source /home/sim/ardupilot/Tools/completion/completion.bash" >> /home/sim/.bashrc

COPY --chown=sim:sim docker/entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
