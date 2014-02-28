#!/bin/bash
n=0
while [ $n -lt 20 ]
do
./osprdaccess -r -l -d 4 &
let n=n+1
sleep 1
done &
