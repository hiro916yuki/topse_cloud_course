#!/bin/bash
# -*- coding: utf-8 -*-

oldwebnodefile=oldwebnode.txt
newwebnodefile=newwebnode.txt

abs_path=$(cd $(dirname $0) && pwd)
prefix_path=$(cd ${abs_path}/../ && pwd)

echo "start mcollective of old web servers"
IFS=$'\n'
file=(`cat $oldwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "start mcollective of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "/etc/init.d/mcollective start"
done

echo "stop mcollective of new web servers"
IFS=$'\n'
file=(`cat $newwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "stop mcollective of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "/etc/init.d/mcollective stop"
done

sleep 5

echo "change loadbalancer setting"
mco facts ipaddress -F fqdn=/^web/ -j | ${prefix_path}/bin/retrieve ip mco --format file > /var/tmp/nginx/nginx.ipset
echo "/var/tmp/nginx/nginx.ipset"
cat /var/tmp/nginx/nginx.ipset

mco puppetd runonce -I lb.nii.localdomain -v
mco service nginx restart -F fqdn=/^lb/ -v

echo "change monitor setting"
mco facts ipaddress -F fqdn=/^web/ -j | ${prefix_path}/bin/retrieve ip mco --format file > /var/tmp/monitor/web.ipset
echo "/var/tmp/monitor/web.ipset"
cat /var/tmp/monitor/web.ipset

mco puppetd runonce -F fqdn=/^monitor/ -v


echo "stop ganglia-monitor of new web servers"
IFS=$'\n'
file=(`cat $newwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "stop ganglica-monitor of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service ganglia-monitor stop"
done

echo "start ganglia-monitor of old web servers"
IFS=$'\n'
file=(`cat $oldwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "start ganglica-monitor of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service ganglia-monitor start"
done

sleep 5

echo "restart gmetad of monitor server"
mco service gmetad restart -F fqdn=/^monitor/ -v

sleep 3

echo "restart nagios3 of monitor server"
monitorip=`mco facts ipaddress -F fqdn=/^monitor/ -j | /root/work/deploy/bin/retrieve ip mco`
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 stop"
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 start"

echo "delete new webnode"
IFS=$'\n'
file=(`cat $newwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "delete web server ${tmpid} (${tmpip})"
	${prefix_path}/bin/deploy instances terminate ${tmpid}
done

mco puppetd runonce -F fqdn=/^monitor/ -v

# restart gmetad
echo "restart gmetad"
mco service gmetad restart -F fqdn=/^monitor/ -v

echo "restart ganglia-monitor"
IFS=$'\n'
file=(`cat $oldwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "restart ganglia-monitor of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service ganglia-monitor restart"
	sleep 2
done

echo "switch_to_old_webnode.sh: finished"
