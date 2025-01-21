FROM ubuntu:20.04

# Paketleri güncelle ve gerekli bağımlılıkları yükle
RUN apt-get update && apt-get install -y \
    openjdk-8-jdk \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Çalışma dizinini belirleyelim
WORKDIR /opt

# JBoss 4.2.2 GA dosyasını konteyner içine kopyalayalım
COPY jboss-4.2.2.GA.zip /opt/

# Arşivi aç ve gereksiz dosyaları temizle
RUN unzip jboss-4.2.2.GA.zip && \
    rm -f jboss-4.2.2.GA.zip

# JAVA_HOME ve JBoss ortam değişkenlerini ayarla
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
ENV JBOSS_HOME=/opt/jboss-4.2.2.GA
ENV PATH="$JBOSS_HOME/bin:$PATH"

# JBoss için default portları açalım
EXPOSE 8080 8443 1099 4444 4445 8009

# JBoss'u başlatma komutu
CMD ["sh", "-c", "$JBOSS_HOME/bin/run.sh -b 0.0.0.0"]
