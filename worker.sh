#!/bin/bash

# Ortak işlemler: Master ve Worker node'lar için geçerli komutlar

#multipass delete worker && multipass purge && multipass launch 24.04 --name worker -c 2 -m 4G -d 10G && multipass shell worker

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

# Kernel modüllerini aktif et
enable_kernel_modules() {
    local start_time=$(date +%s)
    print_message "Aktif kernel modülleri..."
    sudo modprobe overlay
    sudo modprobe br_netfilter
    print_message "Kernel modülleri aktif edildi."
    measure_time $start_time
}

# Kernel modüllerini her başlatmada yükle
configure_kernel_modules() {
    local start_time=$(date +%s)
    print_message "Kernel modüllerini her başlatmada yüklemek için yapılandırma yapılıyor..."
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    print_message "Kernel modülleri her başlatmada yüklenecek şekilde yapılandırıldı."
    measure_time $start_time
}

# Ağ ayarlarını yapılandır
configure_sysctl() {
    local start_time=$(date +%s)
    print_message "Ağ ayarları için kernel parametreleri ayarlanıyor..."
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system
    print_message "Ağ ayarları yapılandırıldı."
    measure_time $start_time
}

# Swap devre dışı bırak
disable_swap() {
    local start_time=$(date +%s)
    print_message "Swap devre dışı bırakılıyor..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    print_message "Swap devre dışı bırakıldı."
    measure_time $start_time
}

# Containerd kurulumu
install_containerd() {
    local start_time=$(date +%s)
    print_message "Containerd kurulumu yapılıyor..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install containerd.io -y
    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd
    sudo systemctl start containerd
    sudo mkdir -p /etc/containerd
    sudo su -c "containerd config default > /etc/containerd/config.toml"
    sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd
    print_message "Containerd kuruldu."
    measure_time $start_time
}

# Kubernetes paketlerini kur
install_kubernetes() {
    local start_time=$(date +%s)
    print_message "Kubernetes paketleri kuruluyor..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl gpg
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    print_message "Kubernetes paketleri kuruldu."
    measure_time $start_time
}

# Worker node'u Kubernetes master'a bağla
join_worker_node() {
    local start_time=$(date +%s)
    print_message "Worker node'u master'a bağlanmaya hazırlanıyor..."
    echo "Master kurulumu tamamlandığında, kubeadm join komutunu buraya girin."
    echo "Komutu girene kadar işlem bekleyecek..."
    read -p "Kubeadm join komutunu girin ve Enter'a basın: " join_command
    sudo $join_command
    print_message "Worker node master'a başarıyla bağlandı."
    measure_time $start_time
}

# Main function to execute the tasks
main() {
    local start_time=$(date +%s)
    enable_kernel_modules
    configure_kernel_modules
    configure_sysctl
    disable_swap
    install_containerd
    install_kubernetes
    join_worker_node
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    print_message "Toplam script çalışma süresi: $minutes dakika ve $seconds saniye"
}

# Run the main function
clear
main

