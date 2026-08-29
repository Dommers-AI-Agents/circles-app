#!/bin/bash
# flick.sh x y1 y2 — multi-point vertical pan (short hold, so cells don't
# read it as a long-press); momentum-free like drag.sh
X=$(python3 -c "print(int(${CFOX:-996} + $1*${CFW:-346}/440))")
Y1=$(python3 -c "print(int(${CFOY:-112} + $2*${CFH:-751}/956))"); Y2=$(python3 -c "print(int(${CFOY:-112} + $3*${CFH:-751}/956))")
YA=$(( Y1 + (Y2-Y1)/4 )); YB=$(( Y1 + (Y2-Y1)/2 )); YC=$(( Y1 + 3*(Y2-Y1)/4 ))
cliclick dd:$X,$Y1 w:40 dm:$X,$YA w:25 dm:$X,$YB w:25 dm:$X,$YC w:25 dm:$X,$Y2 w:120 du:$X,$Y2
