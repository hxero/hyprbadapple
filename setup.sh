#!/usr/bin/env bash
# hyprbadapple setup
# Options:
#   --force        re-generate boxes.bin even if it already exists
#   -h, --help     show this help

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

FORCE=0
for arg in "$@"; do
	case "$arg" in
		--force)   FORCE=1 ;;
		-h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown option: $arg"; exit 1 ;;
	esac
done

c_blue=$'\e[1;34m'; c_green=$'\e[1;32m'; c_yellow=$'\e[1;33m'; c_red=$'\e[1;31m'; c_off=$'\e[0m'
info() { echo "${c_blue}::${c_off} $*"; }
ok()   { echo "${c_green}✓${c_off} $*"; }
warn() { echo "${c_yellow}!${c_off} $*"; }
die()  { echo "${c_red}✗ $*${c_off}" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# guard
for f in init.lua box meti.so baprocess/pack.py baprocess/badapple.webm baprocess/badapple.mp3; do
	[ -e "$f" ] || die "missing $f - run this script from inside the hyprbadapple folder"
done

# ---------------------------------------------------------------- packages
install_deps() {
	local sudo=""
	[ "$(id -u)" -ne 0 ] && sudo="sudo"

	if have pacman; then
		info "Arch-based distro detected"
		$sudo pacman -S --needed --noconfirm mpv socat python python-pip
	elif have apt-get; then
		info "Debian/Ubuntu-based distro detected"
		$sudo apt-get update
		$sudo apt-get install -y mpv socat python3 python3-venv python3-pip
	elif have dnf; then
		info "Fedora-based distro detected"
		$sudo dnf install -y mpv socat python3 python3-pip
	elif have zypper; then
		info "openSUSE detected"
		$sudo zypper install -y mpv socat python3 python3-pip
	elif have xbps-install; then
		info "Void Linux detected"
		$sudo xbps-install -Sy mpv socat python3 python3-pip
	else
		warn "Unknown distro - please install manually: mpv socat python3 python3-pip (+ venv support)"
	fi
}

info "Installing system dependencies (mpv, socat, python)..."
install_deps

for bin in mpv socat python3 hyprctl; do
	have "$bin" || die "'$bin' not found in PATH"
done
ok "mpv, socat, python3, hyprctl found"

chmod +x box start.sh 2>/dev/null || true

# check box wayland libraries
if have ldd && ldd ./box 2>&1 | grep -q "not found"; then
	warn "./box is missing libraries (probably libwayland-client) - install your distro's wayland package"
fi

# python environment
info "Setting up Python environment..."
cd "$DIR/baprocess"
if [ ! -d .venv ]; then
	python3 -m venv .venv || die "python venv failed (on Debian/Ubuntu: sudo apt install python3-venv)"
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
ok "python deps installed"

# process video
mkdir -p output
if [ "$FORCE" -eq 1 ]; then
	info "--force: regenerating everything from the video"
	rm -f boxes.json output/boxes.bin
elif [ -f output/boxes.bin ] && [ -f boxes.json ]; then
	info "boxes.bin already exists (use --force to regenerate) - re-reading stats"
	rm -f output/boxes.bin
fi

info "Processing video (this can take a while the first time)..."
STATS="$(python pack.py | tee /dev/stderr)"
deactivate
cd "$DIR"

MAX_BOXES="$(grep -oP 'most boxes\s*:\s*\K[0-9]+' <<<"$STATS")"
GRID="$(grep -oP 'grid size\s*:\s*\K[0-9]+x[0-9]+' <<<"$STATS")"
GRID_W="${GRID%x*}"; GRID_H="${GRID#*x}"
[ -n "$MAX_BOXES" ] && [ -n "$GRID_W" ] && [ -n "$GRID_H" ] || die "couldn't read stats from pack.py"
[ -f baprocess/output/boxes.bin ] || die "boxes.bin was not generated"
ok "MAX_BOXES=$MAX_BOXES  grid=${GRID_W}x${GRID_H}"

# windows detection
info "Detecting monitor..."
read -r SCALE OFFSET_X OFFSET_Y < <(python3 - "$GRID_W" "$GRID_H" <<'PY'
import json, subprocess, sys
gw, gh = int(sys.argv[1]), int(sys.argv[2])
try:
    mons = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"]))
    m = next((x for x in mons if x.get("focused")), mons[0])
    s = m.get("scale") or 1
    w, h = m["width"] / s, m["height"] / s          # logical pixels
    rl, rt, rr, rb = m.get("reserved", [0, 0, 0, 0]) # bars (left, top, right, bottom)
    usable_h = h - rt - rb
    usable_w = w - rl - rr
    scale = max(1, int(min(usable_h // gh, usable_w // gw)))
    off_x = int(rl + (usable_w - gw * scale) // 2)
    off_y = int(rt + (usable_h - gh * scale) // 2)
    print(scale, off_x, off_y)
except Exception:
    print("0 0 0")
PY
)

if [ "${SCALE:-0}" -le 0 ]; then
	warn "couldn't query hyprctl (are you running inside Hyprland?) - using 1080p defaults"
	SCALE=22; OFFSET_X=256; OFFSET_Y=12
fi
ok "SCALE=$SCALE  OFFSET_X=$OFFSET_X  OFFSET_Y=$OFFSET_Y"

# window launch command prompt
echo
read -rp "Enter window launch command [leave blank to use default]: " CUSTOM_LAUNCH
LAUNCH_CMD="${CUSTOM_LAUNCH:-$DIR/box}"

# write config
[ -f config.lua ] && cp config.lua config.lua.bak

cat > config.lua <<EOF
return {
    LAUNCH = "$LAUNCH_CMD", -- window launch command

    -- relative path to current dir
    BOX_PATH   = "baprocess/output/boxes.bin", -- path to the generated bin file
    AUDIO_PATH = "baprocess/badapple.mp3",

    MAX_BOXES = $MAX_BOXES, -- the \`most boxes\` from python
    FPS         = 30, -- 1-30 framerate (sync playback)

    SCALE      = $SCALE, -- scale  -> resolution height / (grid height)
    OFFSET_X = $OFFSET_X, -- center -> [(resolution width) - (grid width * scale)] / 2
    OFFSET_Y = $OFFSET_Y, -- depends on your top|bottom bars - can be 0 if you want it to fullscreen
};
EOF
ok "wrote config.lua (old one saved as config.lua.bak)"

cat > start.sh << EOF
hyprctl eval "dofile'$DIR/init.lua'"
EOF

# done
echo
ok "Setup complete!"
echo "  Start it with:   cd $DIR && sh start.sh"
echo "  Force stop with: SUPER + U"
