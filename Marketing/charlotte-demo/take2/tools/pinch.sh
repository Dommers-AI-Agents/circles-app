#!/bin/bash
# pinch.sh out|in — option-pinch about window center
CX=$(python3 -c "print(int(${CFOX:-996} + ${CFW:-346}/2))")
CY=$(python3 -c "print(int(${CFOY:-112} + ${CFH:-751}/2))")
if [ "$1" = "out" ]; then A=$((CX+120)); B=$((CX+100)); C=$((CX+80)); D=$((CX+60)); E=$((CX+40)); F=$((CX+20))
else A=$((CX+20)); B=$((CX+40)); C=$((CX+60)); D=$((CX+80)); E=$((CX+100)); F=$((CX+120)); fi
cliclick kd:alt dd:$A,$CY w:200 dm:$B,$CY w:120 dm:$C,$CY w:120 dm:$D,$CY w:120 dm:$E,$CY w:120 dm:$F,$CY w:120 du:$F,$CY ku:alt
