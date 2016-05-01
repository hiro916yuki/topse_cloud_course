#!/bin/bash
# -*- coding: utf-8 -*-

oldwebnodefile=oldwebnode.txt
newwebnodefile=newwebnode.txt

abs_path=$(cd $(dirname $0) && pwd)
prefix_path=$(cd ${abs_path}/../ && pwd)


echo "delete old webnode"
IFS=$'\n'
file=(`cat $oldwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "delete web server ${tmpid} (${tmpip})"
	${prefix_path}/bin/deploy instances terminate ${tmpid}
done

echo "delete_old_webnode.sh: finished"

