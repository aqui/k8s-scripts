#!/bin/bash

# Kullanıcıdan isim soyisim bilgisi al
read -p "Lütfen isim ve soyisim bilgisi girin: " isimsoyisim
read -p "Cluster ismi girin: " clustername
#read -p "Cluster IP adresini girin: " clusterip

openssl rsa -in $clustername/$isimsoyisim.pem -out unencrypted-$isimsoyisim.key
kubectl config set credentials $isimsoyisim --client-certificate=$clustername/$isimsoyisim.crt --client-key=unencrypted-$isimsoyisim.key
kubectl config set-context $clustername-context --cluster=$clustername --user=$isimsoyisim
kubectl config use-context $clustername-context 

