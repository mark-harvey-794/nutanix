#!/bin/bash

# A simple script to collect NIC byte & error counts on 10G interfaces
# Only works with AHV
# Collects: driver version, ring params, rx/tx & error counts and lldpctl for switch connection details

# run on a CVM
# Limitation: only works with AHV.

function allssh () 
{ 
    CMDS=$@;
    DEFAULT_OPTS="-q -o LogLevel=ERROR -o StrictHostKeyChecking=no";
    EXTRA_OPTS=${ALLSSH_OPTS-"-t"};
    OPTS="$DEFAULT_OPTS $EXTRA_OPTS";
    for i in `svmips`;
    do
        if [ "x$i" == "x$IP" ]; then
            continue;
        fi;
        echo "================== "$i" =================";
        /usr/bin/ssh $OPTS $i "source /etc/profile;$@";
    done;
    echo "================== "$IP" =================";
    /usr/bin/ssh $OPTS $IP "source /etc/profile;$@"
}

echo -n "Run started at : "
date
allssh 'ssh root@192.168.5.1 lldpctl 2>/dev/null; for n in $(manage_ovs show_interfaces | grep 10000 | grep True |  cut -c -4); do echo -n "================= hostname: "; echo -n $(ssh root@192.168.5.1 hostname 2> /dev/null); echo ", $n ================="; ssh root@192.168.5.1 ethtool -i $n 2>/dev/null; ssh root@192.168.5.1 ethtool -g $n 2>/dev/null; ssh root@192.168.5.1 ethtool -S $n 2>/dev/null | egrep -v "vf[0-9]|veb|[tr]x_priority" | egrep "[tr]x_packets|[tr]x_bytes|rx_missed_errors|rx_no_buffer_count|[rt]x_flow_control|xon_[rt]x|xoff_[rt]x|[rt]x_size"; done'

echo -n "Run finished at : "
date

