ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS cu

RUN apt-get clean && apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y software-properties-common gettext && \
    apt-get install -y cmake make gcc g++ pkg-config libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev libgtest-dev iproute2 && \
    apt-get update -y && \
    rm -rf /var/lib/apt/lists/*


RUN touch /tmp/cu.log

WORKDIR /cu
COPY . ./

RUN chmod +x /cu/srscu

CMD ["/bin/sh", "-c", "CU_RAN_IP=$(ip addr show dev eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) && CU_F1_IP=$(ip addr show dev eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) && export CU_CP_BIND_ADDR=$CU_RAN_IP && export F1_BIND_ADDR=$CU_F1_IP && envsubst < /cu/cu.template.yml > /cu/cu.yml && /cu/srscu -c /cu/cu.yml & tail -f /tmp/cu.log"]
#CMD ["/bin/sh", "-c", "envsubst < /cu/cu.template.yml > /cu/cu.yml && /cu/srscu -c /cu/cu.yml & tail -f /tmp/cu.log"]
