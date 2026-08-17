#!/usr/bin/env bash
# Export the browser build with version-stamped filenames.
#
# Why not just export and copy: Godot's web export always emits index.wasm and
# index.pck. Those names never change between builds, so a browser that cached
# them once — especially under a long max-age — keeps serving the old game and
# no amount of reloading helps. Worse, index.html revalidates while the pack
# does not, so players end up running a NEW page against an OLD pack.
#
# Naming the files after the build makes the problem structurally impossible:
# a new build requests URLs the browser has never seen.
#
# Usage:  tools/export_web.sh [path-to-godot]
set -euo pipefail

GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD="$(sed -n 's/^const BUILD := "\(.*\)"$/\1/p' core/build_info.gd)"
if [[ -z "$BUILD" ]]; then
	echo "Could not read BUILD from core/build_info.gd" >&2
	exit 1
fi
STEM="hudson-${BUILD}"
echo "Exporting build ${BUILD} as ${STEM}.*"

rm -rf build/web
mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html

cd build/web
# The engine derives every sidecar it loads from the "executable" field, via
# GodotConfig.locate_file("godot.<suffix>") -> "<executable>.<suffix>". So the
# rename has to cover ALL of them, not a list someone remembered to update:
# Godot 4.7 added index.audio.position.worklet.js, and a hardcoded list silently
# left it behind under its old name. The engine then asked for the versioned
# name, got a 404, and nothing said so.
#
# Rename everything the export produced except the page itself and the icons,
# which index.html references by their literal names.
for f in index.*; do
	case "$f" in
		index.html|index.png|index.icon.png|index.apple-touch-icon.png) continue ;;
	esac
	mv "$f" "${STEM}.${f#index.}"
done
sed -i "s/\"executable\":\"index\"/\"executable\":\"${STEM}\"/" index.html
sed -i "s/src=\"index\.js\"/src=\"${STEM}.js\"/" index.html

grep -q "\"executable\":\"${STEM}\"" index.html || { echo "failed to patch executable" >&2; exit 1; }
grep -q "src=\"${STEM}.js\"" index.html || { echo "failed to patch script src" >&2; exit 1; }

# Every sidecar the engine will ask for at runtime must actually be on disk.
# This asserts the invariant directly instead of trusting the rename list, so a
# future engine version that adds another sidecar fails the build loudly rather
# than shipping a 404.
missing=0
for want in $(grep -o 'locate_file("godot\.[^"]*"' "${STEM}.js" \
		| sed 's/locate_file("godot\.//; s/"$//' | sort -u); do
	if [[ ! -f "${STEM}.${want}" ]]; then
		echo "engine will request ${STEM}.${want}, which was not produced" >&2
		missing=1
	fi
done
[[ $missing -eq 0 ]] || exit 1

cd "$ROOT"
# Publish: drop the previous build's versioned files so stale packs are not
# served forever, then copy the new ones in.
find web -maxdepth 1 -name 'hudson-*' -delete
# Also clear stale engine sidecars left under their original names by an older
# version of this script, so what is served is only ever the current export.
for f in web/index.*; do
	case "$(basename "$f")" in
		index.html|index.png|index.icon.png|index.apple-touch-icon.png) continue ;;
	esac
	rm -f "$f"
done
cp build/web/* web/
rm -f web/*.import

echo "Published build ${BUILD}:"
ls -1 web/
