#!/bin/sh
# Скриншоты сцены через виртуальный дисплей: tools/shot.sh res://scene.tscn 1,3 /out/prefix [доп. аргументы]
cd "$(dirname "$0")/.."
SCENE=$1; TIMES=$2; OUT=$3; shift 3
timeout 180 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 res://tests/screenshot.tscn -- scene=$SCENE times=$TIMES out=$OUT "$@" 2>&1 | grep -vE "^$|OpenGL|Godot Engine|^ +at:" | head -30
