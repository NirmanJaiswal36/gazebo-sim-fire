# Docker environment

One image with everything the forest swarm needs:

| | |
|---|---|
| OS | Ubuntu 22.04 (`ros:humble-ros-base-jammy`) |
| Gazebo | Harmonic (gz-sim 8) |
| ROS 2 | Humble + `ros_gz` (Harmonic build) + `cv_bridge` |
| ArduPilot | `995dc62b29` (master), SITL copter pre-built |
| MAVProxy / pymavlink | 1.8.74 / 2.4.49 |
| This repo | plugin built in `build/`, `models/drone_0..7` generated |

The Oak/Pine trees from Fuel are cached in the image, so `forest.sdf` loads
offline. `worlds/`, `config/` and `scripts/` are bind-mounted from your clone,
so edits to them apply without rebuilding. Anything else (the plugin source,
`models/`, `tools/gen_swarm.py`) needs a rebuild.

## Prerequisites (host)

- Docker Engine with the Compose plugin, and your user in the `docker` group
  (`sudo usermod -aG docker $USER`, then log out and back in).
- An X11 session (Wayland with XWayland also works).
- **NVIDIA GPU:** the NVIDIA driver and the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html):
  ```bash
  sudo apt install nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  ```
- **No NVIDIA GPU:** nothing extra. Use the `sim-dri` service below.

## Build

From the repo root. The container user is created with your UID/GID so the
bind mounts and X11 socket work:

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose build
```

The first build takes a while because it compiles ArduPilot SITL.

## Run

Allow the container to use your display. This is needed once per login:

```bash
xhost +SI:localuser:$(whoami)
```

Start the container (NVIDIA):

```bash
docker compose up -d sim
```

Without NVIDIA (Intel/AMD through `/dev/dri`, or Mesa software rendering):

```bash
RENDER_GID=$(getent group render | cut -d: -f3) docker compose --profile dri up -d sim-dri
```

For `sim-dri`, use `sim-dri` in place of `sim` in every command below.

Then run the same steps as [`scripts/README.md`](../scripts/README.md), each in
its own terminal:

```bash
# 1. Gazebo
docker compose exec sim gz sim -v4 -r worlds/forest.sdf

# 2. Drones (N_DRONES in scripts/drones.conf)
docker compose exec sim ./scripts/start_drones.sh

# 3. MAVProxy prompts
docker compose exec sim tmux attach -t drones

# Stop drones / checks
docker compose exec sim ./scripts/stop_drones.sh
docker compose exec sim ./scripts/verify_drones.sh --live
```

Open a general shell, with ROS 2 and ArduPilot completion sourced:

```bash
docker compose exec sim bash
```

Stop everything:

```bash
docker compose down
```

## Networking

The container uses host networking, so nothing needs to be published:

- **QGroundControl on the host or LAN:** UDP `14550 + 10*N` for drone N, as in
  `scripts/README.md`.
- **Extra MAVLink outputs to another machine:** set `REMOTE_GCS_HOST` in a
  `.env` file at the repo root, or in the environment, before `up`. Each drone
  then also sends to `:14550+10N` and `:14551+10N`. Leave it unset to turn this
  off.
- **ROS 2:** `ROS_DOMAIN_ID` defaults to 121. Override it in `.env` the same way.

Example `.env`:

```bash
HOST_UID=1000
HOST_GID=1000
ROS_DOMAIN_ID=121
REMOTE_GCS_HOST=192.168.1.50
```

## ROS 2 camera bridge

```bash
docker compose exec sim bash -ic \
  "ros2 run ros_gz_bridge parameter_bridge --ros-args -p config_file:=config/gz_config.yaml"
```

The topics `/drone_N/camera/image` are visible from the host, or from any
machine on the LAN, with the same `ROS_DOMAIN_ID`.

## Troubleshooting

**`Authorization required` / `could not connect to display`:** Re-run the
`xhost` line, and check that `echo $DISPLAY` on the host matches the container
(`docker compose exec sim printenv DISPLAY`).

**Which GPU is rendering?**

```bash
docker compose exec sim glxinfo -B | grep -E 'renderer|vendor'
```

If this shows `llvmpipe`, rendering is in software. The sim still works, but
the real-time factor will be much lower.

**`could not select device driver "nvidia"`:** The NVIDIA Container Toolkit
isn't installed or configured. Install it (see Prerequisites), or use
`sim-dri`.

**Changed the plugin, `models/` or `tools/`?** Rebuild:
`docker compose build && docker compose up -d --force-recreate sim`.
