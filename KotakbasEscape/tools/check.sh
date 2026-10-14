#!/bin/sh
# Проверка проекта: импорт ресурсов и компиляция всех скриптов в headless-режиме.
cd "$(dirname "$0")/.."
timeout 600 godot --headless --path . --import >/dev/null 2>&1
timeout 300 godot --headless --path . res://tests/compile_all.tscn 2>&1 | grep -E "SCRIPT ERROR|FAIL|ERROR|at: |Скриптов" | grep -v "at: load\|at: start\|at: _create_instance" | head -${1:-60}
