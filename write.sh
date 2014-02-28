#!/bin/bash
a=yahoo
n=0
while [ $n -lt 12 ]
do
new=$a$n
echo $new | ./osprdaccess -w -l -d 2 &
let n=n+1
sleep 3
done &
