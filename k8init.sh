#!/bin/bash

#Installing CNI plugins
sudo dnf -y install containernetworking-plugins

#Installing runc
sudo dnf -y install runc

#Disabling swap
swapoff -a
sed -i -e '/swap/ s/^/#/g' /etc/fstab

#Adding master node ports
sudo firewall-cmd --permanent --add-port={6443,2379,2380,10248-10260,6783,6784}/tcp
sudo firewall-cmd --reload

#Adding worker nodes ports
sudo firewall-cmd --permanent --add-port={10250,30000-32767}/tcp
sudo firewall-cmd --reload

#Network prerequisites
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

#Apply sysctl params without reboot
sudo sysctl --system

#Installing container runtime(docker)
#1. set the repository
sudo yum remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine

#2.install yum utils
sudo yum install -y yum-utils
#3.setting repository for yum utils
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
#4.Installing docker and containerd
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
#Configure docker to use systemd cgroup
sudo mkdir -p /etc/docker
sudo touch /etc/docker/daemon.json
echo '{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}' >> /etc/docker/daemon.json

sudo systemctl daemon-reload

systemctl enable --now docker

systemctl restart docker

#Setting repository for kubernetes
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

#Set Selinux in permissive mode
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

#Installing kubeadm, kubelet, kubectl
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

#Enabling kubeadm
sudo systemctl enable --now kubelet