#!/usr/bin/env bash

# Launch ArduPilot SITL drones against an ALREADY-RUNNING Gazebo.
#
# Gazebo must already be running:
#     gz sim -v4 -r worlds/forest.sdf
#
# tmux layout:
#
#     0:main
#     1:drone0
#     2:drone1
#     3:drone2
#     ...
#     8:drone7
#
# Each drone gets ONE visible tmux window containing MAVProxy.
# The underlying ArduCopter SITL process is launched in a detached
# screen session, so it does NOT create another visible terminal/tmux window.
#
# Navigation:
#     Ctrl-b 1 ... Ctrl-b 8
#     Ctrl-b n
#     Ctrl-b p
#     Ctrl-b w
#
# Usage:
#     ./start_drones.sh
#     ./start_drones.sh 2

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"

# shellcheck source=drones.conf
source "$HERE/drones.conf"

ONLY="${1:-all}"

mkdir -p "$RUN_DIR"


# ============================================================================
# PORT HELPERS
# ============================================================================

fdm_port() {
    echo $((FDM_BASE + 10 * "$1"))
}

tcp_port() {
    echo $((TCP_BASE + 10 * "$1"))
}

gcs_port() {
    echo $((GCS_BASE + 10 * "$1"))
}

drone_dir() {
    echo "$RUN_DIR/$1"
}


# ============================================================================
# GAZEBO CHECK
# ============================================================================

require_gazebo() {
    local i="$1"
    local port

    port="$(fdm_port "$i")"

    if ! ss -lun 2>/dev/null | grep -qE "127\.0\.0\.1:${port}\b"; then
        echo
        echo "ERROR: drone_${i}: nothing is listening on UDP/${port}" >&2
        echo "Start Gazebo first:" >&2
        echo "  cd '$REPO'" >&2
        echo "  gz sim -v4 -r worlds/$WORLD" >&2
        echo
        return 1
    fi
}


# ============================================================================
# SITL TCP CHECK
# ============================================================================

require_free_tcp() {
    local i="$1"
    local port

    port="$(tcp_port "$i")"

    if [[ -n "$(ss -ltnH "sport = :$port" 2>/dev/null)" ]]; then
        echo
        echo "ERROR: drone_${i}: TCP/${port} is already in use." >&2
        echo "An older SITL instance may still be running." >&2
        echo "Run:" >&2
        echo "  '$HERE/stop_drones.sh' $i" >&2
        echo
        return 1
    fi
}


# ============================================================================
# TMUX SESSION
# ============================================================================

ensure_session() {

    # Always start clean.
    #
    # This removes stale drone windows and, importantly, any old
    # ArduCopter windows created by previous versions of this launcher.

    tmux kill-session -t "$SESSION" 2>/dev/null || true

    tmux new-session \
        -d \
        -s "$SESSION" \
        -n main \
        -e "DISPLAY=${DISPLAY:-:0}" \
        -e "XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}" \
        "exec bash"
}


# ============================================================================
# START ONE DRONE
# ============================================================================

start_one_drone() {

    local i="$1"
    local extra=""
    local dir
    local window_index

    dir="$(drone_dir "$i")"
    window_index=$((i + 1))

    mkdir -p "$dir"


    # ------------------------------------------------------------------------
    # Additional MAVLink outputs
    #
    # If REMOTE_GCS_HOST (drones.conf) is set, each drone gets two
    # additional GCS endpoints:
    #   drone i -> REMOTE_GCS_HOST:(14550 + 10*i)
    #   drone i -> REMOTE_GCS_HOST:(14551 + 10*i)
    # ------------------------------------------------------------------------

    local gcs_out1=$((14550 + 10 * i))
    local gcs_out2=$((14551 + 10 * i))

    if [[ -n "${REMOTE_GCS_HOST:-}" ]]; then
        extra="--out ${REMOTE_GCS_HOST}:${gcs_out1} --out ${REMOTE_GCS_HOST}:${gcs_out2}"
    else
        gcs_out1=0
        gcs_out2=0
    fi

    # ------------------------------------------------------------------------
    # Optional extra MAVLink output from drones.conf
    # ------------------------------------------------------------------------

    if [[ -n "${EXTRA_OUT_TEMPLATE:-}" ]]; then
        local N="$i"
        extra="$extra --out $(eval echo "$EXTRA_OUT_TEMPLATE")"
    fi


    # ------------------------------------------------------------------------
    # Optional MAVProxy arguments
    # ------------------------------------------------------------------------

    if [[ -n "${MAVPROXY_ARGS:-}" ]]; then
        extra="$extra -m '$MAVPROXY_ARGS'"
    fi


    # ------------------------------------------------------------------------
    # Optional EEPROM wipe
    # ------------------------------------------------------------------------

    if [[ "${WIPE_EEPROM:-0}" == "1" ]]; then
        extra="$extra -w"
    fi


    # ------------------------------------------------------------------------
    # Launch
    #
    # IMPORTANT:
    #
    #   env -u TMUX
    #
    # prevents sim_vehicle.py's run_in_terminal_window.sh from detecting
    # our outer tmux session and creating another tmux window.
    #
    #   SITL_RITW_TERMINAL="screen -D -m"
    #
    # tells run_in_terminal_window.sh to put the ArduCopter executable into
    # a detached screen session instead of opening xterm/gnome-terminal.
    #
    # Therefore:
    #
    #   visible tmux window -> MAVProxy
    #   detached screen     -> ArduCopter SITL
    # ------------------------------------------------------------------------

    tmux new-window \
        -d \
        -t "$SESSION:$window_index" \
        -n "drone$i" \
        "cd '$dir' && \
         env -u TMUX \
         SITL_RITW_TERMINAL='screen -D -m' \
         sim_vehicle.py \
             -v '$VEHICLE' \
             -f '$FRAME' \
             --model JSON \
             -I '$i' \
             --sysid '$((i + 1))' \
             -l '$HOME_LOCATION' \
             --add-param-file='$REPO/config/gazebo-iris-gimbal.parm' \
             --use-dir='$dir' \
             $extra"


    # If sim_vehicle.py itself exits, keep the MAVProxy window visible
    # so that the error can be read.

    tmux set-option \
        -w \
        -t "$SESSION:drone$i" \
        remain-on-exit on \
        2>/dev/null || true


    # ------------------------------------------------------------------------
    # Display endpoint mapping
    # ------------------------------------------------------------------------

    printf \
        "  drone_%d  sysid %d  fdm %d  tcp %d  mavproxy udp %d  outputs %d,%d  tmux %d  dir %s\\n" \
        "$i" \
        "$((i + 1))" \
        "$(fdm_port "$i")" \
        "$(tcp_port "$i")" \
        "$(gcs_port "$i")" \
        "$gcs_out1" \
        "$gcs_out2" \
        "$window_index" \
        "$dir"
}


# ============================================================================
# LAUNCH
# ============================================================================

if [[ "$ONLY" != "all" ]]; then

    # ------------------------------------------------------------
    # Single drone
    # ------------------------------------------------------------

    require_gazebo "$ONLY"
    require_free_tcp "$ONLY"

    ensure_session
    start_one_drone "$ONLY"

else

    # ------------------------------------------------------------
    # Validate EVERYTHING before starting anything
    # ------------------------------------------------------------

    for ((i = 0; i < N_DRONES; i++)); do
        require_gazebo "$i"
        require_free_tcp "$i"
    done


    # ------------------------------------------------------------
    # Fresh tmux session
    # ------------------------------------------------------------

    ensure_session


    # ------------------------------------------------------------
    # Start drones sequentially
    # ------------------------------------------------------------

    for ((i = 0; i < N_DRONES; i++)); do

        start_one_drone "$i"

        # Prevent several sim_vehicle.py instances from racing through
        # build/startup at exactly the same time.
        sleep 3

    done

fi


# ============================================================================
# FINAL UI
# ============================================================================

echo
echo "============================================================"
echo "  ArduPilot swarm started"
echo "============================================================"
echo
echo "tmux session:"
echo "  tmux attach -t $SESSION"
echo
echo "Window layout:"
echo "  0:main"

for ((i = 0; i < N_DRONES; i++)); do
    echo "  $((i + 1)):drone$i"
done

echo
echo "Navigation:"
echo "  Ctrl-b 1       drone0"
echo "  Ctrl-b 2       drone1"
echo "  Ctrl-b 3       drone2"
echo "  Ctrl-b 4       drone3"
echo "  Ctrl-b 5       drone4"
echo "  Ctrl-b 6       drone5"
echo "  Ctrl-b 7       drone6"
echo "  Ctrl-b 8       drone7"
echo "  Ctrl-b n       next window"
echo "  Ctrl-b p       previous window"
echo "  Ctrl-b w       window chooser"
echo "  Ctrl-b d       detach"
echo
echo "Stop drones:"
echo "  $HERE/stop_drones.sh"
echo