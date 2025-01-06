#!/bin/bash

read -p "Sertifika klasör ismi (context'te kullanılacak): " certfolder

mkdir ./$certfolder

cd $certfolder

read -p "SSH Kullanıcı adı: " USERNAME
read -p "SSH Sunucu IP adresi: " SERVER_IP
read -s -p "SSH Şifre: " PASSWORD
sshpass -p "$PASSWORD" scp "$USERNAME@$SERVER_IP:/etc/kubernetes/pki/ca.crt" .

echo ""

read -p "isimsoyisim: " isimsoyisim

cp ~/.ssh/id_rsa ./"$isimsoyisim.key"

cp ./"$isimsoyisim.key" ./"$isimsoyisim.key.bk"

ssh-keygen -p -m PEM -f ./"$isimsoyisim.key"

mv ./"$isimsoyisim.key" ./"$isimsoyisim.pem"

openssl req -new -key ./"$isimsoyisim.pem" -out ./"$isimsoyisim.csr" -subj "/CN=$isimsoyisim/O=Dev"

echo "CSR ve PEM dosyaları oluşturuldu: ./$isimsoyisim.pem ve ./$isimsoyisim.csr"

openssl rsa -in ./$isimsoyisim.pem -out ./unencrypted-$isimsoyisim.key

sshpass -p "$PASSWORD" ssh "$USERNAME@$SERVER_IP" "mkdir -p /home/$USERNAME/client-certs/$isimsoyisim"

sshpass -p "$PASSWORD" scp ./$isimsoyisim.csr "$USERNAME@$SERVER_IP:/home/$USERNAME/client-certs/$isimsoyisim"

export BASE64_CSR=$(cat "$isimsoyisim.csr" | base64 | tr -d '\n')

cat <<EOF | envsubst > "$isimsoyisim-csr.yaml"
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: "$isimsoyisim"
spec:
  groups:
  - system:unauthenticated
  request: $BASE64_CSR
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF
sshpass -p "$PASSWORD" scp ./$isimsoyisim-csr.yaml "$USERNAME@$SERVER_IP:/home/$USERNAME/client-certs/$isimsoyisim"
REMOTE_YAML_PATH="/home/$USERNAME/client-certs/$isimsoyisim/$isimsoyisim-csr.yaml"
sshpass -p "$PASSWORD" ssh "$USERNAME@$SERVER_IP" "kubectl apply -f \"$REMOTE_YAML_PATH\""
sshpass -p "$PASSWORD" ssh "$USERNAME@$SERVER_IP" "kubectl certificate approve $isimsoyisim"
sshpass -p "$PASSWORD" ssh "$USERNAME@$SERVER_IP" "kubectl get csr $isimsoyisim -o jsonpath='{.status.certificate}' | base64 -d > \"/home/$USERNAME/client-certs/$isimsoyisim/$isimsoyisim.crt\""
sshpass -p "$PASSWORD" scp "$USERNAME@$SERVER_IP:/home/$USERNAME/client-certs/$isimsoyisim/$isimsoyisim.crt" .

kubectl config set credentials $isimsoyisim --client-certificate=./$certfolder/$isimsoyisim.crt --client-key=./$certfolder/unencrypted-$isimsoyisim.key
kubectl config set-context $certfolder-context --cluster=$certfolder --user=$isimsoyisim
kubectl config use-context $certfolder-context
