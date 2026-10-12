# Six independent drones in forest.sdf

Six `iris_with_gimbal` drones in one Gazebo world. Each is a plain
single-vehicle ArduPilot SITL setup — its own `arducopter`, its own MAVProxy
console, its own ports. They share nothing but the world. Nothing here
coordinates them.

## Run it

**1. Start Gazebo yourself** (the scripts never touch it):

```bash
cd ~/ardupilot_gazebo
gz sim -v4 -r worlds/forest.sdf
```

**2. Start the drones:**

```bash
./scripts/start_drones.sh        # all six
./scripts/start_drones.sh 2      # just drone 2
```

Per drone this runs exactly one ordinary single-vehicle launch:

```bash
sim_vehicle.py -v ArduCopter -f gazebo-iris --model JSON \
               -I N --sysid N+1 -l <home> --add-param-file=... --use-dir=...
```

You get **one MAVProxy console window per drone**. For the command prompt:

```bash
tmux attach -t drones     # Ctrl-b w to pick drone0..drone5, Ctrl-b d to detach
```

**3. Stop the drones** — this leaves Gazebo running:

```bash
./scripts/stop_drones.sh         # all
./scripts/stop_drones.sh 2       # just drone 2
```

Stop Gazebo yourself, by quitting its window or Ctrl-C in its terminal. Prefer
Ctrl-C (SIGINT) over `kill -9`: ArduPilotPlugin's lock-step wait only breaks on
a signal (`ArduPilotPlugin.cc:1209-1213`).

## Ports

Drone N gets `base + 10*N` on everything, matching ArduPilot's `-I N`.

| N | model | sysid | fdm (Gazebo) | SITL TCP | MAVProxy UDP |
|---|---|---|---|---|---|
| 0 | `drone_0` | 1 | 9002 | 5760 | 14550 |
| 1 | `drone_1` | 2 | 9012 | 5770 | 14560 |
| 2 | `drone_2` | 3 | 9022 | 5780 | 14570 |
| 3 | `drone_3` | 4 | 9032 | 5790 | 14580 |
| 4 | `drone_4` | 5 | 9042 | 5800 | 14590 |
| 5 | `drone_5` | 6 | 9052 | 5810 | 14600 |

Each drone has its own MAVProxy, so **each UDP port carries exactly one
vehicle**. Point QGroundControl at 14550 for drone_0, 14570 for drone_2, etc.

Gimbal topics: `/drone_N/gimbal/cmd_roll|cmd_pitch|cmd_yaw`.

## Flying one

Go to that drone's tmux window and use it like any single vehicle — no
`vehicle N` switching, it is the only one there:

```
mode guided
arm throttle
takeoff 15
rc 7 1200        # gimbal pitch down (RC6/7/8 = roll/pitch/yaw)
```

## Adding MAVProxy outputs

At runtime, from that drone's prompt:

```
output add 192.168.1.50:14550
output list
```

For every drone, in `scripts/drones.conf` — `$N` is the drone index, so use it
or all six land on one endpoint:

```bash
EXTRA_OUT_TEMPLATE="127.0.0.1:$((15000 + N))"
MAVPROXY_ARGS="--streamrate=10"
```

Other knobs there: `N_DRONES`, `WIPE_EEPROM` (set 0 to keep param changes across
restarts), `HOME_LOCATION`.

## Verify

```bash
./scripts/verify_drones.sh          # static only
./scripts/verify_drones.sh --live   # also checks running drones
```

Checks: exactly one plane collision in the world (the DART LCP-hang guard),
generated models in sync, unique `fdm_port_in`, six sockets owned by **one**
server, each GCS port resolving to its expected sysid, sim advancing, and all 18
gimbal topics wired 1 publisher → 1 subscriber.

## Regenerating the drone models

`models/drone_0..5/` are generated and gitignored:

```bash
python3 tools/gen_swarm.py            # rewrite
python3 tools/gen_swarm.py --check    # fail if stale
```

It transforms the real `models/iris_with_gimbal/model.sdf` and asserts a hit
count for every substitution, so an upstream change fails loudly instead of
emitting a subtly wrong drone. Shipped models are never modified, so
`iris_runway.sdf` and `iris_warehouse.sdf` keep working unchanged.

Spawn poses are plain literals in `worlds/forest.sdf` (~line 126) — edit freely.

## Seeing them in the GUI

They are spread up to ~33 m out in a forest of 100 trees, so at the default
camera they are easy to miss even though they load fine. `forest.sdf` carries a
`<gui>` block whose camera frames all six (`<camera_pose>` near line 72).

To reach one: **Entity Tree** panel → right-click `drone_2` → **Move to**, or
**Follow** to track it in flight.

## Things that will bite you

**No MAVProxy console windows?** A tmux session inherits the tmux *server's*
environment, not your shell's. If a tmux server was already running with a
stale or empty `DISPLAY`, the wx console never appears. `start_drones.sh` passes
`DISPLAY`/`XAUTHORITY` explicitly with `tmux new-session -e`, but that only
applies to a session it creates — if one already exists it is reused as-is. If
consoles are missing, `tmux kill-server` and start again.

**Start Gazebo running, not paused.** Starting paused deadlocks the lock-step
handshake: SITL resends the same servo frame once a second while nothing steps,
the copies queue, and on unpause the plugin drains them and then sees only
`Duplicate input frame` forever while SITL sits on `No JSON sensor message
received`.

**A stale Gazebo does not fail loudly — it splits your traffic.** Two servers
can *both* bind all six FDM ports, because the plugin's socket is
`SO_REUSEADDR`. No error, just two vehicles fighting over one stream. If
something is weird, check exactly one process owns them:

```bash
ss -lunp | grep -E ':(9002|9012|9022|9032|9042|9052)\b'
```

**Lock-step has no timeout recovery.** On a missed packet the lock-step branch
resends state and waits forever (`ArduPilotPlugin.cc:1531-1534`), so one dead
SITL silently freezes *every* drone — and Gazebo itself — with nothing in the
log. If the sim stops advancing, check all six `arducopter` are alive
(`pgrep -xc arducopter`).

**Never `pkill -f 'gz sim'`** — any shell whose command line merely mentions
that string matches too, including the killer.

**Expect RTF ≈ 0.27** with six drones and six cameras. Under lock-step ArduPilot
follows sim time, so flight behaviour stays correct — it just runs slower than
wall clock.
