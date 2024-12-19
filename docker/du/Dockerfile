ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS du

RUN apt-get clean && apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y software-properties-common gettext && \
    apt-get install -y cmake make gcc g++ pkg-config libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev libgtest-dev libzmq3-dev iproute2 && \
    apt-get update -y && \
    rm -rf /var/lib/apt/lists/*

RUN touch /tmp/du.log

WORKDIR /du
COPY . ./

RUN chmod +x /du/srsdu
RUN ls -al /du # Verifique se o arquivo srscu está no contêiner

CMD ["/bin/sh", "-c", "RU_SDR_TX_PORT=$(ip addr show dev eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) && \ 
F1AP_BIND_ADDR=$(ip addr show dev eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) && \
export RU_SDR_TX_PORT=$RU_SDR_TX_PORT && export F1AP_BIND_ADDR=$F1AP_BIND_ADDR && \
envsubst < /du/du.template.yml > /du/du.yml && /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]

#CMD ["/bin/bash", "-c", "envsubst < /du/du.template.yml > /du/du.yml && /du/srsdu -c du.yml & tail -f /tmp/du.log"]