#!/bin/bash
cluster_lb=$1
proxy_lb=$2
cluster_domain=$3
ssh_key=$4
nfs_mount=$5
#server:/data

function getIPs {
    for i in $(cat /opt/ibm/cluster/hosts); do
    if [[ $i =~ [A-Za-z]+ ]];then
        master_count=-1
        worker_count=-1
        if [[ $i =~ master ]];then
        master_count=0
        fi
        if [[ $i =~ worker ]];then
        worker_count=0
        fi
        continue
    fi

    if [[ $master_count -ge 0 ]];then
        masters[$master_count]=$i
        ((master_count++))
    fi

    if [[ $worker_count -ge 0 ]];then
        workers[$worker_count]=$i
        ((worker_count++))
    fi
    done
}

getIPs

echo "ssh_key=${ssh_key}" > /tmp/wdp.conf
echo "virtual_ip_address_1=${cluster_lb}" >> /tmp/wdp.conf
echo "virtual_ip_address_2=${proxy_lb}" >> /tmp/wdp.conf

master1_node=${masters[0]}

for((i=0;i<${#masters[@]};i++));do
    echo "master_node_$((i+1))=${masters[i]}" >> /tmp/wdp.conf
    echo "master_node_path_$((i+1))=/ibm" >> /tmp/wdp.conf
done

for((i=0;i<${#workers[@]};i++));do
    echo "worker_node_$((i+1))=${workers[i]}" >> /tmp/wdp.conf
    if [[ "$nfs_mount" == "" ]];then
        echo "worker_node_data_$((i+1))=/data" >> /tmp/wdp.conf
    fi
    echo "worker_node_path_$((i+1))=/ibm" >> /tmp/wdp.conf
done

if [[ "$nfs_mount" != "" ]];then
    echo $nfs_mount | awk -F: '{print "nfs_server="$1"\nnfs_dir="$2}' >> /tmp/wdp.conf
fi

echo "ssh_port=22" >> /tmp/wdp.conf
# add cloud additional data
admin_pwd=$(grep default_admin_password /opt/ibm/cluster/config.yaml | awk -F: '{print $2}')
echo "cloud=softlayer" >> /tmp/wdp.conf
echo "cloud_data=${cluster_domain},${admin_pwd}" >> /tmp/wdp.conf
# xfer to master 1 node
ssh_user=root
chmod 0600 ${ssh_key}
scp -i ${ssh_key} -o StrictHostKeyChecking=no /tmp/wdp.conf ${ssh_user}@${master1_node}:~/
ssh -i ${ssh_key} -o StrictHostKeyChecking=no ${ssh_user}@${master1_node} "mkdir /ibm;sudo mv wdp.conf /ibm;chown root:root /ibm/wdp.conf"

tar -cvzf /tmp/icp-cluster.tar.gz /opt/ibm/cluster/cfc-certs /opt/ibm/cluster/config.yaml /opt/ibm/cluster/hosts
scp -i ${ssh_key} -o StrictHostKeyChecking=no /tmp/icp-cluster.tar.gz ${ssh_user}@${master1_node}:/tmp
ssh -i ${ssh_key} -o StrictHostKeyChecking=no ${ssh_user}@${master1_node} "mkdir -p /opt/ibm/cluster; if [ ! -f /opt/ibm/cluster/config.yaml ];then tar -xvzf /tmp/icp-cluster.tar.gz -C /;fi"
