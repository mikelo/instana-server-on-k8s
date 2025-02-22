#!/bin/bash

### Installing K8s tools
function installing-k8s-tools {
  echo "----> installing-k8s-tools"

  # Add K8s repo
  cat <<'EOF' | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

  # Set SELinux in permissive mode (effectively disabling it)
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

  # Check the available candidates by:
  #  dnf --showduplicates list kubelet
  #  dnf --showduplicates list kubeadm
  #  dnf --showduplicates list kubectl
  sudo dnf install -y kubelet-$K8S_VERSION kubeadm-$K8S_VERSION kubectl-$K8S_VERSION --disableexcludes=kubernetes

  # Enable kubelet
  sudo systemctl enable kubelet
  
  logme "$color_green" "DONE"
}

### Installing K8s CRI with CRI-O
function installing-k8s-cri {
  echo "----> installing-k8s-cri"

  sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo
  sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.repo
  sudo dnf install cri-o -y

  # Enable and start cri-o service
  sudo systemctl enable crio
  sudo systemctl start crio
  
  logme "$color_green" "DONE"
}

### Bootstrapping K8s
function bootstrapping-k8s {
  echo "----> bootstrapping-k8s"

  # 1. Disable the swap. To make it permanent, update the /etc/fstab and comment/remove the line with swap
  #   sudo vi /etc/fstab
  #   UUID=0aa6ce7f-b825-4b08-9515-b1e7a2bdb9a9 / ext4 defaults,noatime 0 1
  #   UUID=f909ac6c-f5e5-4f9a-874a-8aabecc4f674 /boot ext4 defaults,noatime 0 0
  #   #LABEL=SWAP-xvdb1	swap	swap	defaults,nofail	0	0
  sudo swapoff -a

  # 2. Create the .conf file to load the modules at bootup
  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter

  # 3. Set up required sysctl params, these persist across reboots.
  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
  sudo sysctl --system

  # 4. Bootstrap it
  # Note: we customize the service-node-port-range: 443-32767
  # To change existing cluster, `vi /etc/kubernetes/manifests/kube-apiserver.yaml`,
  # add `--service-node-port-range=80-32767`, save then `sudo systemctl restart kubelet`
  #sudo kubeadm init --pod-network-cidr=192.168.0.0/16
  sudo kubeadm init --config manifests/kubeadm-init-conf.yaml
  
  logme "$color_green" "DONE"
}

### Getting ready with K8s
function getting-ready-k8s {
  echo "----> getting-ready-k8s"

  # Copy over the kube config for admin access
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  # Remove the taint as we have only one node
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  
  logme "$color_green" "DONE"
}

### Installing K8s CNI with Calico
function installing-k8s-cni {
  echo "----> installing-k8s-cni"

  kubectl apply -f "${CALICO_MANIFEST_FILE}"
  
  logme "$color_green" "DONE"
}
