# Kubernetes Cluster Setup Script

This script automates the process of setting up a Kubernetes cluster on a machine. It includes installation of basic dependencies, containerd, Kubernetes packages, network plugins (Calico, MetalLB), and Ingress controllers. It also configures the Kubernetes master node, disables swap, configures firewall, and installs Helm.

## Prerequisites
Before running this script, ensure that:
- Your machine is running Ubuntu 20.04 or later.
- You have `sudo` privileges.
- The machine has internet access to download dependencies and Docker packages.

## Features
1. **Firewall Disabling**: Disables the firewall (UFW).
2. **Basic Dependency Installation**: Installs basic dependencies like `net-tools`, `curl`, `apt-transport-https`, etc.
3. **Helm Installation**: Installs Helm, a package manager for Kubernetes.
4. **Kernel Configuration**: Configures kernel modules necessary for Kubernetes networking.
5. **Swap Disabling**: Disables swap and ensures it's permanently off.
6. **Containerd Installation**: Installs and configures containerd as the container runtime.
7. **Kubernetes Installation**: Installs Kubernetes components (`kubelet`, `kubeadm`, `kubectl`).
8. **Master Node Initialization**: Initializes the Kubernetes master node with `kubeadm`.
9. **Calico Network Plugin**: Installs Calico for networking in Kubernetes.
10. **MetalLB Configuration**: Configures MetalLB for LoadBalancer services.
11. **NGINX Ingress Controller Installation**: Installs the NGINX Ingress Controller and applies example Ingress resources.
12. **Kubernetes Dashboard**: Installs the Kubernetes dashboard with `helm` and creates an `admin-user` service account.

## Usage
1. Clone this repository and navigate to the script directory.
2. Make the script executable:
   ```bash
   chmod +x master.sh
