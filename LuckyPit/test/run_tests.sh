#!/bin/sh
# Java SE tests over the real game logic: save integrity and balance simulation.
#   test/run_tests.sh            quick (300 runs per bot)
#   RUNS=1000 test/run_tests.sh  closer numbers
set -e
cd "$(dirname "$0")/.."
OUT=build/test
rm -rf $OUT && mkdir -p $OUT
LOGIC="Rng Symbol Card CardManager Stats GameState EffectManager SlotMachine DebtManager Shop EventManager Op SaveManager"
SRC=""
for c in $LOGIC; do SRC="$SRC src/luckypit/$c.java"; done
javac -nowarn --release 8 -encoding UTF-8 -cp lib/midpapi20.jar:lib/cldcapi11.jar -d $OUT $SRC test/SaveTest.java test/Sim.java
cp res/cards.dat $OUT/
java -cp $OUT:lib/midpapi20.jar SaveTest
for s in 0 1 2 3; do java -cp $OUT Sim ${RUNS:-300} $s; done
java -cp $OUT Sim ${MCRUNS:-100} 4
