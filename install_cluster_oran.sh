#!/bin/bash
# Author: Cleriston Willian (cleriston@cpqd.com.br)
# Description: Installing prerequisites for cluster VOLTHA Version 2.10.4
# Cluster K8s version 1.23.9 with Conteinerd
# Last update: 02/06/2023
#-------------------------------[ Global Variables ]------------------------------------

# Log file location
LOG="/tmp/prereq-voltha.log"

# Variables for log colors
YELLOW="\033[0;33m"
GREEN="\033[0;32m"
NC="\033[0m"

set -x

IP_HOST=""
K8S_VERSION="1.21.0"
#-------------------------------[ Functions ]-------------------------------------------


function PreInstallPackages {
    sudo apt update
    sudo apt install -y linux-generic-hwe-18.04 curl apt-transport-https ca-certificates net-tools vim ifupdown unzip iotop git make gnupg-agent gcc

}

function InstallHelm {
    sudo curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    sudo chmod 700 get_helm.sh
    sudo ./get_helm.sh
    sudo rm get_helm.sh
}

function RepoK8s {
    sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
    sudo echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >> ~/kubernetes.list
    sudo mv ~/kubernetes.list /etc/apt/sources.list.d
    sudo apt-get update
}



function PreInstallK8s {
    sudo sed -e '/swap/ s/^#*/#/' -i /etc/fstab
    sudo swapoff -a 
    sudo apt-get install -y kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00 docker.io
    sudo apt-mark hold kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00
    sudo systemctl enable --now kubelet
    sudo modprobe overlay
    sudo modprobe br_netfilter
    sudo usermod -aG docker $USER
}

function ConfigsK8s {
    sudo touch /etc/sysctl.d/kubernetes.conf
    sudo chmod 777 /etc/sysctl.d/kubernetes.conf
    cat <<EOF > /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system
}


function configsKubeAdm {
    sudo chmod 777 /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    echo 'Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true --fail-swap-on=false"' >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
}

function firewall {
    sudo iptables -F && iptables -X
    sudo iptables -t nat -F && iptables -t nat -X;
    sudo iptables -t raw -F && iptables -t raw -X;
    sudo iptables -t mangle -F && iptables -t mangle -X;
}
function InstallKubernetes { 
    sudo kubeadm config images pull --kubernetes-version v${K8S_VERSION}  
    sudo kubeadm init --pod-network-cidr 10.140.0.0/16 --service-cidr=10.150.0.0/16 --kubernetes-version v${K8S_VERSION} --apiserver-advertise-address=${IP_HOST}  
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

function ConfigKubeAdm {
    sudo chown $USER. /var/lib/kubelet/ -R
    cat <<EOF > /var/lib/kubelet/kubeadm-flags.env
    KUBELET_KUBEADM_ARGS="--network-plugin=cni --pod-infra-container-image=k8s.gcr.io/pause:3.4.1 --allowed-unsafe-sysctls='net.*' --feature-gates=CPUManager=true --topology-manager-policy=best-effort --feature-gates=KubeletPodResources=true --feature-gates=KubeletPodResourcesGetAllocatable=true"
EOF
}

function RemoveTaintKubernetes {
    kubectl taint nodes --all node-role.kubernetes.io/master-
    kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
}

function InstallCalico {
    helm repo add projectcalico https://docs.projectcalico.org/charts
    helm repo add incubator https://charts.helm.sh/incubator
    helm repo update
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml
    kubectl create -f custom-resources.yaml     
}

function CheckInstallK8s {    
    sleep 50 && kubectl get nodes && kubectl get pods -A
}

#--------------------------------[ Start of Script Execution ]------------------------------------
echo -e "${YELLOW}$(date +%d/%m%Y) - $(date +%T) - Start cluster installation${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
# PreInstallPackages

# InstallHelm

RepoK8s

PreInstallK8s

ConfigsK8s

configsKubeAdm

firewall

InstallKubernetes

ConfigKubeAdm

RemoveTaintKubernetes

InstallCalico

CheckInstallK8s

echo "---------------------------------------------------------" | tee --append "${LOG}"
newgrp docker
