#!/bin/bash

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

main(){
    local start_time=$(date +%s)
    MASTER_IP=$(hostname -I | awk '{print $1}')
    install_dashboard
    DASHBOARD_PORT=$(kubectl get svc -n kubernetes-dashboard kubernetes-dashboard-kong-proxy -o jsonpath='{.spec.ports[0].nodePort}')
    DASHBOARD_TOKEN=$(kubectl create token admin-user -n kubernetes-dashboard)
    print_message "Shogun says:"
    touch dashboard_addr
    echo "Dashboard: https://$MASTER_IP:$DASHBOARD_PORT" >> dashboard_addr
    echo "" >> dashboard_addr
    echo $DASHBOARD_TOKEN >> dashboard_addr
    echo "" >> dashboard_addr
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
