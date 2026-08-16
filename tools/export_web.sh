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
# The engine derives <executable>.wasm / .pck / .audio.worklet.js from the
# "executable" field; index.js is named by the script tag. Rename both, and
# repoint the page at them.
for ext in wasm pck audio.worklet.js js; do
	[[ -f "index.${ext}" ]] && mv "index.${ext}" "${STEM}.${ext}"
done
sed -i "s/\"executable\":\"index\"/\"executable\":\"${STEM}\"/" index.html
sed -i "s/src=\"index\.js\"/src=\"${STEM}.js\"/" index.html

grep -q "\"executable\":\"${STEM}\"" index.html || { echo "failed to patch executable" >&2; exit 1; }
grep -q "src=\"${STEM}.js\"" index.html || { echo "failed to patch script src" >&2; exit 1; }

cd "$ROOT"
# Publish: drop the previous build's versioned files so stale packs are not
# served forever, then copy the new ones in.
find web -maxdepth 1 -name 'hudson-*' -delete
cp build/web/* web/
rm -f web/*.import

echo "Published build ${BUILD}:"
ls -1 web/
