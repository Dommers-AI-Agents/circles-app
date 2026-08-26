#!/bin/bash
# drag.sh x1 y1 x2 y2 [holdms] — no-momentum drag
X1=$(python3 -c "print(int(${CFOX:-996} + $1*${CFW:-346}/440))"); Y1=$(python3 -c "print(int(${CFOY:-112} + $2*${CFH:-751}/956))")
X2=$(python3 -c "print(int(${CFOX:-996} + $3*${CFW:-346}/440))"); Y2=$(python3 -c "print(int(${CFOY:-112} + $4*${CFH:-751}/956))")
cliclick dd:$X1,$Y1 w:${5:-300} dm:$X2,$Y2 w:150 du:$X2,$Y2
