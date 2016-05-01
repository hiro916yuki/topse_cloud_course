#!/bin/bash
# -*- coding: utf-8 -*-

oldwebnodefile=oldwebnode.txt
newwebnodefile=newwebnode.txt

if [ -e $oldwebnodefile ]; then
        echo "delete $oldwebnodefile"
        rm $oldwebnodefile
fi

if [ -e $newwebnodefile ]; then
        echo "delete $newwebnodefile"
        rm $newwebnodefile
fi

echo "save ip and id of current web servers to $oldwebnodefile"
webnodeids=`mco facts ipaddress -F fqdn=/^web/ -v | ../bin/retrieve instance_id mco`
for id in $webnodeids; do
        ip=`mco facts ipaddress -F fqdn=/^web.${id}/ -v | ../bin/retrieve ip mco`
        echo "$ip $id" >> $oldwebnodefile
done

oldwebnodenum=`cat $oldwebnodefile |wc -l`
echo "number of old webnode: $oldwebnodenum"

cat $oldwebnodefile | while read line
do
        echo "ip: `echo $line | cut -d' ' -f1`";
        echo "id: `echo $line | cut -d' ' -f2`";
done

abs_path=$(cd $(dirname $0) && pwd)
prefix_path=$(cd ${abs_path}/../ && pwd)

IFS=$'\n'
file=(`cat $oldwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service puppetd stop"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service puppetd disable"
done
IFS=$' \t\n'

# get Web servers information

old_instance_ids=($( mco facts ipaddress -F fqdn=/^web/ -v -j | ${prefix_path}/bin/retrieve instance_id mco ))
instance_num=${#old_instance_ids[*]}
echo "old_instances: ${old_instance_ids[@]}"

instance_num=`wc -l ${oldwebnodefile} | cut -d' ' -f1`
echo "instance_num = ${instance_num}"
if [ ${instance_num} -eq 0 ] ; then
  echo "ERROR: No web instance found."
  exit 1
fi

# launch instance

echo "launch web instances"
instance_ids=
for ((i=1; i<=${instance_num}; i++)); do
  instance_id=$(${prefix_path}/bin/deploy instances launch web | ${prefix_path}/bin/retrieve instance_id cloud)
  if [ ${i} -eq 1 ]; then
    instance_ids="${instance_id}"
  else
    instance_ids="${instance_id} ${instance_ids}"
  fi
done
echo "instance ids: ${instance_ids}"

# wait instance state running
for instance_id in ${instance_ids}; do
  echo "wait until ${instance_id} launched"
  ${prefix_path}/bin/deploy instances wait ${instance_id}
done
echo "running instance"

# add deploy server ipaddr to webnode
mail_ipaddr=`mco facts ipaddress -F fqdn=/^mail/ -j | ${prefix_path}/bin/retrieve ip mco`
echo "mail server: ${mail_ipaddr}"

db_ipaddr=`mco facts ipaddress -F fqdn=/^db/ -j | ${prefix_path}/bin/retrieve ip mco`
echo "db server: ${db_ipaddr}"

deploy_ipaddr=`/sbin/ip route get 8.8.8.8 |head -1 |awk '{print $7}'`

for instance_id in ${instance_ids}; do
  ipaddr=`${prefix_path}/bin/deploy instances describe --instanceids=${instance_id} --key=ipaddr | ${prefix_path}/bin/retrieve ip cloud`
  echo "deploy ${instance_id}:${ipaddr}"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "echo \"${deploy_ipaddr} deploy.nii.localdomain\" >> /etc/hosts"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "echo \"${mail_ipaddr} mail.nii.localdomain\" >> /etc/hosts"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "echo \"${db_ipaddr} db.nii.localdomain\" >> /etc/hosts"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "/etc/init.d/puppet stop"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "/etc/init.d/mcollective stop"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "rm -rf /var/lib/puppet/ssl"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "/etc/init.d/puppet start"
  ${prefix_path}/bin/deploy ssh exec ${ipaddr} "/etc/init.d/mcollective start"
done

# add puppetca to puppetmaster
echo 'start puppet cert'

while [[ "${certnum}" != "${instance_num}" ]]; do
  sleep 5
  certnum="$( puppet cert list | grep web | wc -l )"
done
puppet cert sign --all

echo 'accepted cert list'
puppet cert list --all

# wait for it to finish the execution of the puppet agent
for instance_id in ${instance_ids}; do
  fqdn="web.${instance_id}.nii.localdomain"
  echo "[${fqdn}]"
  max=30

  while :
  do
    for ((i=1; i<=${max}; i++)); do
      ipaddr=$( mco facts ipaddress -I ${fqdn} | ${prefix_path}/bin/retrieve ip mco )
      echo "[${fqdn}] ip: ${ipaddr}"
      if [ ${ipaddr} ]; then
        echo "[${fqdn}] Retrieved IP address by mco"
	echo "${ipaddr} ${instance_id}" >> $newwebnodefile
        break
      fi
      sleep 10
    done

    if [ ${ipaddr} ]; then
      break
    fi

    web_node_ipaddress=`${prefix_path}/bin/deploy instances describe --instanceids=${instance_id} --key=ipaddr | ${prefix_path}/bin/retrieve ip cloud`
    ${prefix_path}/bin/deploy ssh exec ${web_node_ipaddress} "/etc/init.d/mcollective stop"
    ${prefix_path}/bin/deploy ssh exec ${web_node_ipaddress} "/etc/init.d/mcollective start"

    sleep 10
  done

  echo "facts created: ${instance_id}"

  # restart the tomcat to run war file that was distributed
  # ${prefix_path}/bin/deploy ssh exec ${ipaddr} "service tomcat6 stop"
  # ${prefix_path}/bin/deploy ssh exec ${ipaddr} "service tomcat6 start"
  mco service tomcat6 restart -F fqdn=${fqdn} -v

  # prevent the automatic update ot puppet agent
  mco puppetd disable -F fqdn=${fqdn} -v
done


echo "stop mcollective of old web servers"
IFS=$'\n'
file=(`cat $oldwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "stop mcollective of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "/etc/init.d/mcollective stop"
done
IFS=$' \t\n'

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

echo "restart nagios3 of monitor server"
monitorip=`mco facts ipaddress -F fqdn=/^monitor/ -j | /root/work/deploy/bin/retrieve ip mco`
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 stop"
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 start"

echo "start ganglia-monitor of new web servers"
IFS=$'\n'
file=(`cat $newwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "start ganglia-monitor of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service ganglia-monitor start"
	sleep 1
done
IFS=$' \t\n'

sleep 2

echo "stop ganglia-monitor of old web servers"
IFS=$'\n'
file=(`cat $oldwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "stop ganglia-monitor of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service ganglia-monitor stop"
	sleep 1
done
IFS=$' \t\n'

sleep 5

echo "restart gmetad of monitor server"
mco service gmetad restart -F fqdn=/^monitor/ -v

sleep 15

echo "restart nagios3 of monitor server"
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 stop"
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 start"

sleep 20

echo "restart ganglia-monitor"
for ((i=0; i < 2; i++)); do
        IFS=$'\n'
        file=(`cat $newwebnodefile`)
        for line in "${file[@]}"; do
                tmpip=`echo $line | cut -d' ' -f1`
                tmpid=`echo $line | cut -d' ' -f2`
                echo "restart ganglia-monitor of web server ${tmpid} (${tmpip})"
                ${prefix_path}/bin/deploy ssh exec ${tmpip} "service ganglia-monitor restart"
                sleep 5
        done
	IFS=$' \t\n'
done

echo "restart nagios3 of monitor server"
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 stop"
${prefix_path}/bin/deploy ssh exec $monitorip "service nagios3 start"

sleep 30

echo "restart ganglia-monitor"
IFS=$'\n'
file=(`cat $newwebnodefile`)
for line in "${file[@]}"; do
        tmpip=`echo $line | cut -d' ' -f1`
        tmpid=`echo $line | cut -d' ' -f2`
        echo "restart ganglia-monitor of web server ${tmpid} (${tmpip})"
        ${prefix_path}/bin/deploy ssh exec ${tmpip} "service ganglia-monitor restart"
        sleep 5
done
IFS=$' \t\n'

echo "New webnodes are deployed." 
echo "Execute ./delete_old_webnode.sh after you confirm new webnodes have no problem."
echo "If you find any probrem in new webnodes, execute ./switch_to_old_webnode.sh "
echo "to use old webnodes again and delete new webnodes."

echo "deploy_and_switch_to_new_webnode.sh: finished"
