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
RUN ls -al /du # Verifique se o arquivo srsdu está no contêiner

CMD ["/bin/sh", "-c", "\
  echo '[DU Dockerfile] Detectando interfaces de rede...'; \
  ip addr show; \
  for iface in eth0 eth1 eth2; do \
    DU_F1_IP=$(ip addr show dev $iface 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n1); \
    if [ ! -z \"$DU_F1_IP\" ]; then \
      echo \"[DU Dockerfile] Interface $iface detectada com IP: $DU_F1_IP\"; \
      break; \
    fi; \
  done; \
  export F1AP_BIND_ADDR=${F1AP_BIND_ADDR:-$DU_F1_IP}; \
  export NRU_BIND_ADDR=${NRU_BIND_ADDR:-$DU_F1_IP}; \
  if [ -z \"$NRU_EXT_ADDR\" ] || [ \"$NRU_EXT_ADDR\" = \"auto\" ]; then \
    export NRU_EXT_ADDR=$DU_F1_IP; \
  fi; \
  export METRICS_ADDR=${METRICS_ADDR:-metrics_listener}; \
  export METRICS_PORT=${METRICS_PORT:-55555}; \
  echo \"[DU Dockerfile] Variáveis de ambiente configuradas:\"; \
  echo \"  F1AP_CU_CP_ADDR=$F1AP_CU_CP_ADDR\"; \
  echo \"  F1AP_BIND_ADDR=$F1AP_BIND_ADDR\"; \
  echo \"  NRU_BIND_ADDR=$NRU_BIND_ADDR\"; \
  echo \"  NRU_EXT_ADDR=$NRU_EXT_ADDR\"; \
  echo \"  METRICS_ADDR=$METRICS_ADDR\"; \
  echo \"  METRICS_PORT=$METRICS_PORT\"; \
  echo \"  RU_SDR_TX_PORT=$RU_SDR_TX_PORT\"; \
  echo \"  RU_SDR_RX_PORT=$RU_SDR_RX_PORT\"; \
  echo \"  GNB_ID=$GNB_ID\"; \
  echo '[DU Dockerfile] Gerando configuração a partir do template...'; \
  envsubst < /du/du.template.yml > /du/du.yml && \
  echo '[DU Dockerfile] Configuração gerada:'; \
  cat /du/du.yml | head -n 20; \
  echo '[DU Dockerfile] Iniciando srsRAN DU...'; \
  /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]

