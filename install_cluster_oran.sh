#!/bin/bash
# Author: Isadora Figueiredo (isadorafm@cpqd.com.br)
# Description: Installing k8s cluster
#-------------------------------[ Global Variables ]------------------------------------

# Log file location
LOG="/tmp/k8s_install.log"

# Variables for log colors
YELLOW="\033[0;33m"
GREEN="\033[0;32m"
NC="\033[0m"

set -x

DOCKER_VERSION="5:24.0.6-1~ubuntu.20.04~focal"
IPADDRESS=""
K8S_VERSION="1.21.0"
CIDR_POD_NETWORK="10.140.0.0/16"
CIDR_SERVICE="10.150.0.0/16"
#-------------------------------[ Functions ]-------------------------------------------
function InstallPackages {
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

function InstallDocker {
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install docker-ce=${DOCKER_VERSION}
}

function PreInstallK8s {
    sudo sed -e '/swap/ s/^#*/#/' -i /etc/fstab
    sudo swapoff -a 
    sudo apt-get install -y kubelet=${K8S_VERSION}-00 kubeadm=${K8S_VERSION}-00 kubectl=${K8S_VERSION}-00
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
    sudo kubeadm init --pod-network-cidr ${CIDR_POD_NETWORK} --service-cidr=${CIDR_SERVICE} --kubernetes-version v${K8S_VERSION} --apiserver-advertise-address=${IPADDRESS}  
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

function ConfigKubelet {
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

function multus {
    cd $HOME
    wget https://github.com/k8snetworkplumbingwg/multus-cni/archive/refs/tags/v3.7.1.zip && unzip v3.7.1.zip
    kubectl apply -f $HOME/multus-cni-3.7.1/images/multus-daemonset.yml
    sudo rm v3.7.1.zip
}

#--------------------------------[ Start of Script Execution ]------------------------------------
echo -e "${YELLOW}$(date +%d/%m%Y) - $(date +%T) - Start cluster installation${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Installing Packages...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
InstallPackages 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Installing Helm...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
InstallHelm 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Adding k8s repositories...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
RepoK8s 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Installing Docker...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
InstallDocker 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Installing kubelet, kuectl, kubeadm and configuring swap...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
PreInstallK8s 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Configuring k8s...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
ConfigsK8s 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Configuring Kubeadm...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
configsKubeAdm 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Configuring Iptables...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
firewall 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Installing k8s...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
InstallKubernetes 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Configuring Kubelet...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
ConfigKubelet 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Removing Taint...${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
RemoveTaintKubernetes 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Installing Calico Custom..${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
InstallCalico 1> >(tee --append "${LOG}")

echo -e "${GREEN}$(date +%d/%m%Y) - $(date +%T) - Installing Multus ..${NC}" | tee --append "${LOG}"
echo | tee --append "${LOG}"
multus 1> >(tee --append "${LOG}")

echo -e "${YELLOW}$(date +%d/%m%Y) - $(date +%T) - End of installation of Cluster K8S version ${K8S_VERSION}.${NC}" | tee --append "${LOG}"
echo -e "${YELLOW} Run 'kubectl get pods -A' to see if all pods is ready and running.${NC}" | tee --append "${LOG}"
echo "---------------------------------------------------------" | tee --append "${LOG}"
newgrp docker
