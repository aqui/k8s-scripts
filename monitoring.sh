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

main(){
    local start_time=$(date +%s)
    MASTER_IP=$(hostname -I | awk '{print $1}')
    install_monitoring
    install_dashboard 
    kubectl get pods -A --field-selector=status.phase=Succeeded -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers | awk '{print "kubectl delete pod -n "$1" "$2}' | sh
    GRAFANA_PORT=$(kubectl get svc -n monitoring kubeprostack-grafana -o jsonpath='{.spec.ports[0].nodePort}')
    PROMETHEUS_PORT=$(kubectl get svc -n monitoring kubeprostack-kube-promethe-prometheus -o jsonpath='{.spec.ports[0].nodePort}')
    ALERTMANAGER_PORT=$(kubectl get svc -n monitoring kubeprostack-kube-promethe-alertmanager -o jsonpath='{.spec.ports[0].nodePort}')
    DASHBOARD_PORT=$(kubectl get svc -n kubernetes-dashboard kubernetes-dashboard-kong-proxy -o jsonpath='{.spec.ports[0].nodePort}')
    WORKER_JOIN=$(kubeadm token create --print-join-command)
    DASHBOARD_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
    KIBANA_PORT=$(kubectl get svc -n efk-stack kibana -o jsonpath='{.spec.ports[0].nodePort}')
    print_message "Shogun says:"
    touch monitoring_addr
    echo "Grafana: http://$MASTER_IP:$GRAFANA_PORT" > monitoring_addr
    echo "Grafana username: admin" >> monitoring_addr
    echo "Grafana password: prom-operator" >> monitoring_addr
    echo "Prometheus: http://$MASTER_IP:$PROMETHEUS_PORT" >> monitoring_addr
    echo "Alert Manager: http://$MASTER_IP:$ALERTMANAGER_PORT" >> monitoring_addr
    echo "" >> monitoring_addr
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
