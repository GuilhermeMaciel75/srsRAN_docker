ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS du

RUN apt-get clean && apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y software-properties-common && \
    apt-get install -y cmake make gcc g++ pkg-config libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev libgtest-dev libzmq3-dev && \
    apt-get update -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /du
COPY . ./

RUN chmod +x /du/srsdu
RUN ls -al /du # Verifique se o arquivo srscu está no contêiner

ENTRYPOINT ["/du/srsdu", "-c", "du.yml"]
