#!/usr/bin/env bash
# Checks. Static ones always run; live ones only with --live.
#   ./scripts/verify_drones.sh          static only
#   ./scripts/verify_drones.sh --live   also check running drones
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
source "$HERE/drones.conf"
cd "$REPO"

PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

echo "== world =="
# Count plane collisions with XML comments stripped. A naive grep for '<plane>'
# also matches the explanatory comment above ground_plane and reports 2.
# Coincident plane collisions become identical infinite DART PlaneShapes and
# hang the LCP solver -- this is the guard for that.
n=$(python3 -c "
import re;s=open('worlds/$WORLD').read()
print(len(re.findall(r'<plane>', re.sub(r'<!--.*?-->','',s,flags=re.S))))")
[[ "$n" == "1" ]] && ok "exactly one plane collision" || bad "plane collisions = $n (must be 1)"
[[ $(grep -c 'model://drone_' "worlds/$WORLD") -eq $N_DRONES ]] \
  && ok "$N_DRONES drone includes" || bad "drone includes != $N_DRONES"

echo "== models =="
python3 tools/gen_swarm.py --check >/dev/null 2>&1 \
  && ok "generated models match tools/gen_swarm.py" || bad "generated models are stale"
bad_xml=0
for ((i=0;i<N_DRONES;i++)); do
  python3 -c "import xml.dom.minidom;xml.dom.minidom.parse('models/drone_$i/model.sdf')" 2>/dev/null \
    || bad_xml=$((bad_xml+1))
  grep -q '<plane>' "models/drone_$i/model.sdf" 2>/dev/null && bad "drone_$i adds a plane collision"
done
[[ $bad_xml -eq 0 ]] && ok "all model.sdf well-formed" || bad "$bad_xml malformed model.sdf"
[[ -z $(grep -h '<fdm_port_in>' models/drone_*/model.sdf | sort | uniq -d) ]] \
  && ok "fdm_port_in unique per drone" || bad "duplicate fdm_port_in"
grep -q '>/gimbal/cmd_' models/drone_*/model.sdf \
  && bad "a drone still uses the shared /gimbal/cmd_ topic" \
  || ok "gimbal topics are per-drone"
[[ -z $(git status --porcelain models/iris_with_gimbal/model.sdf) ]] \
  && ok "shipped iris_with_gimbal untouched" || bad "shipped model was modified"

if [[ "${1:-}" != "--live" ]]; then
  echo; echo "static: $PASS passed, $FAIL failed  (--live to check running drones)"
  exit $((FAIL>0))
fi

echo "== gazebo =="
bound=0; for ((i=0;i<N_DRONES;i++)); do
  ss -lun 2>/dev/null | grep -qE "127\.0\.0\.1:$((FDM_BASE+10*i))\b" && bound=$((bound+1)); done
[[ $bound -eq $N_DRONES ]] && ok "$N_DRONES fdm ports bound" || bad "fdm ports bound = $bound"
owners=$(ss -lunp 2>/dev/null | grep -oP "127\.0\.0\.1:$FDM_BASE\b.*?pid=\K[0-9]+" | sort -u | wc -l)
# Two servers can both bind these (SO_REUSEADDR), silently splitting the FDM
# traffic instead of failing. Exactly one owner is required.
[[ "$owners" -le 1 ]] && ok "fdm ports owned by a single server" \
                      || bad "$owners servers sharing fdm ports"
it=$(timeout 12 gz topic -e -t "/world/$WORLD_NAME/stats" -n 1 2>/dev/null | grep -oP 'iterations: \K[0-9]+')
[[ -n "$it" && "$it" -gt 0 ]] && ok "sim advancing (iterations=$it)" \
  || bad "not advancing -- one stalled SITL wedges every drone under lock_step"

echo "== drones =="
n=$(pgrep -xc arducopter || true)
[[ "$n" -eq $N_DRONES ]] && ok "$N_DRONES arducopter running" || bad "arducopter = $n"
# Each drone has its OWN MAVProxy, so its GCS port carries exactly one sysid.
for ((i=0;i<N_DRONES;i++)); do
  got=$(timeout 40 python3 -c "
from pymavlink import mavutil
m=mavutil.mavlink_connection('udp:127.0.0.1:$((GCS_BASE+10*i))')
h=m.wait_heartbeat(timeout=20); print(h.get_srcSystem() if h else 'none')" 2>/dev/null)
  [[ "$got" == "$((i+1))" ]] && ok "drone_$i udp/$((GCS_BASE+10*i)) -> sysid $got" \
                             || bad "drone_$i udp/$((GCS_BASE+10*i)) -> sysid $got, want $((i+1))"
done

echo "== gimbal isolation =="
mis=0
for ((i=0;i<N_DRONES;i++)); do for j in roll pitch yaw; do
  info=$(timeout 8 gz topic -i -t "/drone_$i/gimbal/cmd_$j" 2>/dev/null)
  p=$(echo "$info" | sed -n '/Publishers/,/Subscribers/p' | grep -cE '^\s+\S+, gz\.msgs')
  s=$(echo "$info" | sed -n '/Subscribers/,$p'            | grep -cE '^\s+\S+, gz\.msgs')
  [[ "$p" -eq 1 && "$s" -eq 1 ]] || mis=$((mis+1))
done; done
[[ $mis -eq 0 ]] && ok "all $((N_DRONES*3)) gimbal topics: 1 publisher, 1 subscriber" \
                 || bad "$mis gimbal topics mis-wired"

echo; echo "$PASS passed, $FAIL failed"
exit $((FAIL>0))
