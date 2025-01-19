# Configure MetalLB

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

# Main function to execute the tasks
main() {
    local start_time=$(date +%s)
    MASTER_IP=$(hostname -I | awk '{print $1}')
    configure_metallb "${MASTER_IP}-${MASTER_IP}"
    install_ingress
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
