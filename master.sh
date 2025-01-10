#!/bin/bash

#multipass delete master && multipass purge && multipass launch 24.04 --name master -c 4 -m 12G -d 15G && multipass shell master

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
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address="$MASTER_IP" --control-plane-endpoint="$MASTER_IP" --ignore-preflight-errors=Swap
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    print_message "Kubernetes master initialized."
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
    print_message "Calico network plugin installed."
    measure_time $start_time
    print_message "Waiting for Calico pods to be up..."
    wait_for_pods
}

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

# Configure MetalLB
configure_metallb() {
    local start_time=$(date +%s)
    print_message "Configuring MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
    print_message "Waiting for MetalLB pods to be up..."
    wait_for_pods

    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - $1
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default
EOF
    print_message "MetalLB configured."
    measure_time $start_time
}

# Install NGINX Ingress and apply example Ingress
install_ingress() {
    local start_time=$(date +%s)
    print_message "Installing NGINX Ingress..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
    print_message "Waiting for NGINX Ingress pods to be up..."
    kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec": {"type": "LoadBalancer"}}'
    print_message "NGINX Ingress Controller installed."
    wait_for_pods
#    echo "waiting for additional 1 minute"
#    sleep 1m
    # Apply the example Ingress configuration
    #cat <<EOF | kubectl apply -f -
    #apiVersion: networking.k8s.io/v1
    #kind: Ingress
    #metadata:
    #  name: example-ingress
    #  namespace: default
    #  annotations:
    #    nginx.ingress.kubernetes.io/rewrite-target: /
    #spec:
    #  rules:
    #  - host: example.local
    #    http:
    #      paths:
    #      - path: /
    #        pathType: Prefix
    #        backend:
    #          service:
    #            name: example-service
    #            port:
    #              number: 80
    #EOF
    print_message "Example Ingress applied."
    measure_time $start_time
}

# Main function to execute the tasks
main() {
    local start_time=$(date +%s)
    disable_firewall
    install_dependencies
    install_helm
    configure_kernel
    disable_swap
    install_containerd
    install_kubernetes
    initialize_master
    install_calico
    MASTER_IP=$(hostname -I | awk '{print $1}')
    configure_metallb "${MASTER_IP}-${MASTER_IP}"  # Example IP range
    install_ingress
    print_message "To join worker nodes, run the following command on each worker node:"
    kubeadm token create --print-join-command
    echo "https://$MASTER_IP"
    #Completed görünen pod'ları sil'
    kubectl delete pod --field-selector=status.phase=Completed -A
    #Dashboard
    # Add kubernetes-dashboard repository
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    # Deploy a Helm Release named "kubernetes-dashboard" using the kubernetes-dashboard chart
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
cat <<EOF > dashboard-kong.yaml
kong:
  proxy:
    type: NodePort
  http:
    enabled: true
EOF
    helm upgrade kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard -f dashboard-kong.yaml -n kubernetes-dashboard
cat <<EOF > dashboard-user.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: "admin-user"
type: kubernetes.io/service-account-token
EOF
    kubectl apply -f dashboard-user.yaml
    kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath={".data.token"} | base64 -d
    kubectl create namespace monitoring
    helm install my-grafana grafana/grafana --namespace monitoring
    
    echo "Graphana username: admin"
    echo "Graphana admin password:"
    kubectl get secret --namespace monitoring my-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
   
    echo ""
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    print_message "Total script execution time: $minutes minutes and $seconds seconds"
}

# Run the main function
clear
main

