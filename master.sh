#!/bin/bash

#multipass delete master && multipass purge && multipass launch 24.04 --name master -c 5 -m 14G -d 30G && multipass shell master

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
    wait_for_pods
    print_message "Waiting for NGINX Ingress pods to be up..."
    kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec": {"type": "LoadBalancer"}}'
    print_message "NGINX Ingress Controller installed."
    measure_time $start_time
}

install_monitoring() {
    local start_time=$(date +%s)
    kubectl create namespace monitoring
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm install kubeprostack --namespace monitoring prometheus-community/kube-prometheus-stack
    print_message "Waiting for monitoring pods to be up..."
    wait_for_pods
    #kubectl --namespace monitoring port-forward svc/kubeprostack-kube-promethe-prometheus 9090
    #kubectl --namespace monitoring port-forward svc/kubeprostack-kube-promethe-alertmanager 9093
    #kubectl --namespace monitoring port-forward svc/kubeprostack-grafana 8080:80
    kubectl patch svc kubeprostack-kube-promethe-prometheus -n monitoring -p '{"spec": {"type": "NodePort", "ports": [{"port": 9090, "nodePort": 30090}]}}'
    kubectl patch svc kubeprostack-kube-promethe-alertmanager -n monitoring -p '{"spec": {"type": "NodePort", "ports": [{"port": 9093, "nodePort": 30093}]}}'
    kubectl patch svc kubeprostack-grafana -n monitoring -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "nodePort": 30080}]}}'
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: monitoring
  name: prometheus-role
rules:
  - apiGroups: [""]
    resources:
      - pods
      - services
      - endpoints
      - nodes
      - nodes/proxy
      - configmaps
    verbs: ["get", "list", "watch"]
EOF
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: prometheus-rolebinding
  namespace: monitoring
subjects:
  - kind: ServiceAccount
    name: default
    namespace: monitoring
roleRef:
  kind: Role
  name: prometheus-role
  apiGroup: rbac.authorization.k8s.io
EOF
    #kubectl get secret kubeprostack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
    measure_time $start_time
}

install_dashboard(){
    local start_time=$(date +%s)
    print_message "Installing Kubernetes Dashboard..."
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
    wait_for_pods
    #kubectl patch svc kubernetes-dashboard-web -n kubernetes-dashboard -p '{"spec": {"type": "NodePort"}}'
    kubectl patch svc kubernetes-dashboard-kong-proxy -n kubernetes-dashboard -p '{"spec": {"type": "NodePort"}}'
cat <<EOF | kubectl apply -f -
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
EOF
    kubectl -n kubernetes-dashboard create token admin-user
    print_message "Kubernetes Dashboard installed."
    measure_time $start_time
}

# Main function to execute the tasks
main() {
    local start_time=$(date +%s)
    MASTER_IP=$(hostname -I | awk '{print $1}')
    disable_firewall
    install_dependencies
    install_helm
    configure_kernel
    disable_swap
    install_containerd
    install_kubernetes
    initialize_master
    install_calico
    configure_metallb "${MASTER_IP}-${MASTER_IP}"
    install_ingress
    install_monitoring
    install_dashboard 
    kubectl get pods -A --field-selector=status.phase=Succeeded -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers | awk '{print "kubectl delete pod -n "$1" "$2}' | sh
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    GRAFANA_PORT=$(kubectl get svc -n monitoring kubeprostack-grafana -o jsonpath='{.spec.ports[0].nodePort}')
    PROMETHEUS_PORT=$(kubectl get svc -n monitoring kubeprostack-kube-promethe-prometheus -o jsonpath='{.spec.ports[0].nodePort}')
    ALERTMANAGER_PORT=$(kubectl get svc -n monitoring kubeprostack-kube-promethe-alertmanager -o jsonpath='{.spec.ports[0].nodePort}')
    DASHBOARD_PORT=$(kubectl get svc -n kubernetes-dashboard kubernetes-dashboard-kong-proxy -o jsonpath='{.spec.ports[0].nodePort}')
    WORKER_JOIN=$(kubeadm token create --print-join-command)
    DASHBOARD_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
    print_message "Shogun says:"
    touch app_ip_addr
    echo "Grafana: http://$MASTER_IP:$GRAFANA_PORT" > app_ip_addr
    echo "Grafana username: admin" >> app_ip_addr
    echo "Grafana password: prom-operator" >> app_ip_addr
    echo "Prometheus: http://$MASTER_IP:$PROMETHEUS_PORT" >> app_ip_addr
    echo "Alert Manager: http://$MASTER_IP:$ALERTMANAGER_PORT" >> app_ip_addr
    echo "Dashboard: https://$MASTER_IP:$DASHBOARD_PORT" >> app_ip_addr
    echo "" >> app_ip_addr
    echo "Dashboard Bearer Token: $DASHBOARD_TOKEN" >> app_ip_addr
    echo "" >> app_ip_addr
    echo "Worker join command:" $WORKER_JOIN >> app_ip_addr
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    echo "Total script execution time: $minutes minutes and $seconds seconds"
    print_message "All set"
}

# Run the main function
clear
main

