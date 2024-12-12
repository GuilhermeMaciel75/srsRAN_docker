ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS cu

RUN apt-get clean && apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y software-properties-common && \
    apt-get install -y cmake make gcc g++ pkg-config libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev libgtest-dev && \
    apt-get update -y && \
    rm -rf /var/lib/apt/lists/*


RUN touch /tmp/cu.log

WORKDIR /cu
COPY . ./

RUN chmod +x /cu/srscu
RUN ls -al /cu # Verifique se o arquivo srscu está no contêiner

CMD ["/bin/bash", "-c", "/cu/srscu -c cu.yml & tail -f /tmp/cu.log"]
#CMD ["/bin/sh", "-c", "/cu/srscu -c cu.yml"]
