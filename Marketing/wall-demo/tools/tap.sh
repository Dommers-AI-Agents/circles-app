#!/bin/bash
# tap.sh x y (device pts 440x956)
X=$(python3 -c "print(int(${CFOX:-996} + $1*${CFW:-346}/440))")
Y=$(python3 -c "print(int(${CFOY:-112} + $2*${CFH:-751}/956))")
cliclick c:$X,$Y
