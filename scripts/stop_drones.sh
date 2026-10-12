#!/usr/bin/env bash
# Stop the ArduPilot SITL drones. LEAVES GAZEBO RUNNING.
#
# Gazebo is yours to start and stop; this only cleans up what start_drones.sh
# launched. To stop Gazebo too, quit its window or Ctrl-C the terminal it runs
# in -- and prefer SIGINT over SIGKILL, because ArduPilotPlugin's lock-step wait
# only breaks on a signal (ArduPilotPlugin.cc:1209-1213).
#
#   ./scripts/stop_drones.sh        all drones
#   ./scripts/stop_drones.sh 2      just drone 2
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=drones.conf
source "$HERE/drones.conf"

ONLY="${1:-all}"

if [[ "$ONLY" != "all" ]]; then
  # Single drone: we do have to look at command lines here, since that is the
  # only thing distinguishing one instance from another. Narrow the pattern to
  # the full binary path and this instance's own port so it cannot match a
  # passing shell, and never match the bare string "mavproxy.py".
  pkill -f "bin/arducopter .*-I$ONLY( |\$)" 2>/dev/null \
    && echo "  drone_$ONLY arducopter stopped" || true
  pkill -f "bin/mavproxy.py .*tcp:127\.0\.0\.1:$((TCP_BASE + 10 * ONLY))( |\$)" 2>/dev/null \
    && echo "  drone_$ONLY mavproxy stopped" || true
  tmux kill-window -t "$SESSION:drone$ONLY" 2>/dev/null \
    && echo "  drone_$ONLY window closed" || true
  exit 0
fi

# Match by exact process NAME (-x), never by command line (-f).
#
# pkill -f 'mavproxy.py' matches any process whose command line merely mentions
# the string -- including the shell you typed this into, and this script's own
# parent. That is not theoretical: it killed the calling shell during testing.
# Both arducopter and mavproxy.py report those exact names in comm, so -x is
# both safer and sufficient. sim_vehicle.py needs no explicit kill: it exits
# once its child dies, and killing the tmux session finishes the job.
#
# Kill politely, verify, then insist. MAVProxy's --console forks wx GUI children
# that ignore SIGTERM; SIGTERMing only the parent orphans them and they pile up
# across start/stop cycles (28 accumulated in testing).
kill_group() {
  local name=$1 n
  n=$(pgrep -xc "$name" 2>/dev/null || true)
  [[ "${n:-0}" -eq 0 ]] && return 0
  pkill -x "$name" 2>/dev/null || true
  for ((t = 0; t < 10; t++)); do
    sleep 0.5
    [[ "$(pgrep -xc "$name" 2>/dev/null || true)" -eq 0 ]] && { echo "  $name stopped ($n)"; return 0; }
  done
  pkill -9 -x "$name" 2>/dev/null || true
  sleep 1
  local left; left=$(pgrep -xc "$name" 2>/dev/null || true)
  [[ "${left:-0}" -eq 0 ]] && echo "  $name stopped ($n, needed SIGKILL)" \
                           || echo "  WARNING: $left $name still alive" >&2
}

kill_group arducopter
kill_group mavproxy.py

tmux kill-session -t "$SESSION" 2>/dev/null && echo "  tmux session killed" || true

a=$(pgrep -xc arducopter  2>/dev/null || true)
m=$(pgrep -xc mavproxy.py 2>/dev/null || true)
if [[ "${a:-0}" -eq 0 && "${m:-0}" -eq 0 ]]; then
  echo "  all drones stopped (Gazebo left running)"
else
  echo "  WARNING: ${a:-0} arducopter, ${m:-0} mavproxy still alive" >&2
fi
