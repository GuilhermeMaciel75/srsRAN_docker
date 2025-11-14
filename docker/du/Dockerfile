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

# Versão com console interativo (pode usar docker attach)
CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]

# Versão antiga (background com logs em arquivo)
#CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]