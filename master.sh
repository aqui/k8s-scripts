#!/bin/bash

#multipass delete master && multipass purge && multipass launch 24.04 --name master -c 2 -m 8G -d 30G && multipass shell master

# Wait for all pods in the given namespace to be running
wait_for_pods() {
    print_message "Checking if all pods in all namespaces are in a healthy state (Running, Succeeded, or Completed)..."
    while true; do
        # Pods that are not in Running, Succeeded, or Completed status in any namespace
        PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded,status.phase!=Completed --no-headers)
        if [ -z "$PODS" ]; then
            print_message "All pods in all namespaces are in a healthy state."
            break
        fi
        sleep 5
    done
}

# Function to print colored messages
print_message() {
    local message=$1
    echo -e "\033[34m===========================\033[0m"
    echo -e "\033[34m$message\033[0m"
    echo -e "\033[34m===========================\033[0m"
}

# Function to calculate and print execution time
measure_time() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    echo -e "\033[32mTime taken: $minutes minutes and $seconds seconds\033[0m"
}

# Disable firewall
disable_firewall() {
    local start_time=$(date +%s)
    print_message "Disabling firewall..."
    sudo ufw disable
    print_message "Firewall disabled."
    measure_time $start_time
}

# Install basic dependencies
install_dependencies() {
    local start_time=$(date +%s)
    print_message "Installing basic dependencies..."
    sudo apt update
    sudo apt install -y net-tools apt-transport-https ca-certificates curl gpg
    print_message "Basic dependencies installed."
    measure_time $start_time
}

# Install Helm
install_helm() {
    local start_time=$(date +%s)
    print_message "Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    print_message "Helm installed."
    measure_time $start_time
}

# Configure kernel modules
configure_kernel() {
    local start_time=$(date +%s)
    print_message "Configuring kernel modules..."
    sudo modprobe overlay
    sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system
    print_message "Kernel modules configured."
    measure_time $start_time
}

# Disable swap
disable_swap() {
    local start_time=$(date +%s)
    print_message "Disabling swap..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    print_message "Swap disabled."
    measure_time $start_time
}

# Install containerd
install_containerd() {
    local start_time=$(date +%s)
    print_message "Installing containerd..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y containerd.io
    sudo systemctl enable --now containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd
    print_message "Containerd installed."
    measure_time $start_time
}

# Install Kubernetes packages
install_kubernetes() {
    local start_time=$(date +%s)
    print_message "Installing Kubernetes packages..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt update
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    print_message "Kubernetes packages installed."
    measure_time $start_time
}

# Initialize Kubernetes master node
initialize_master() {
    local start_time=$(date +%s)
    print_message "Initializing Kubernetes master node..."
    MASTER_IP=$(hostname -I | awk '{print $1}')
    #--kubernetes-version=1.31.0
    #--ignore-preflight-errors=NumCPU
    #--ignore-preflight-errors=Mem
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address="$MASTER_IP" --control-plane-endpoint="$MASTER_IP" --ignore-preflight-errors=Swap
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    measure_time $start_time
}

# Install Calico network plugin
install_calico() {
    local start_time=$(date +%s)
    print_message "Installing Calico network plugin..."
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    #kubectl taint nodes --all node-role.kubernetes.io/master-
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/custom-resources.yaml
    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
    print_message "Waiting for Calico pods to be up..."
    wait_for_pods
    print_message "Calico network plugin installed."
    measure_time $start_time
}

install_linkerd(){
    local start_time=$(date +%s)
    print_message "Installing Linkerd..."
    curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
    echo 'export PATH=$HOME/.linkerd2/bin:$PATH' >> ~/.bashrc && source ~/.bashrc
    linkerd version
    linkerd check --pre
    linkerd install --crds | kubectl apply -f -
    linkerd install | kubectl apply -f -
    linkerd check
    linkerd viz install | kubectl apply -f - # install the on-cluster metrics stack
    linkerd check
    wait_for_pods
    linkerd viz install > linkerd-install.yaml
    sed -i '/-enforced-host=/d' linkerd-install.yaml
    kubectl apply -f linkerd-install.yaml
    kubectl patch svc web -n linkerd-viz -p '{"spec": {"type": "NodePort", "ports": [{"port": 8084, "targetPort": 8084, "nodePort": 30084}]}}'
    kubectl patch svc web -n linkerd-viz -p '{"spec": {"type": "NodePort", "ports": [{"port": 9994, "targetPort": 9994, "nodePort": 30994}]}}'
    #linkerd viz dashboard &
    #kubectl get -n kubernetes-dashboard deploy -o yaml | linkerd inject - | kubectl apply -f -
    print_message "Linkerd installed."
    measure_time $start_time
}

# Main function to execute the tasks
main() {
    local start_time=$(date +%s)
    MASTER_IP=$(hostname -I | awk '{print $1}')
    export EDITOR=nano
    disable_firewall
    install_dependencies
    install_helm
    configure_kernel
    disable_swap
    install_containerd
    install_kubernetes
    initialize_master
    install_calico
    install_linkerd
    touch join_command
    touch linkerd_addr    
    WORKER_JOIN=$(kubeadm token create --print-join-command)
    echo "sudo" $WORKER_JOIN > join_command
    LINKERD_PORT=$(kubectl get svc -n linkerd-viz web -o jsonpath='{.spec.ports[0].nodePort}')
    echo "Linkerd: http://$MASTER_IP:$LINKERD_PORT" > linkerd_addr
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    echo "Total script execution time: $minutes minutes and $seconds seconds"
    kubectl get pods -A --field-selector=status.phase=Succeeded -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers | awk '{print "kubectl delete pod -n "$1" "$2}' | sh
    print_message "All set"
}

# Run the main function
clear
main

