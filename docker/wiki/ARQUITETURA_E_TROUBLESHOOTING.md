# Arquitetura srsRAN Split 5G com Docker Swarm: Guia Completo de Implementação e Troubleshooting

## Sumário Executivo

Este documento apresenta a implementação completa de uma arquitetura 5G standalone (SA) utilizando srsRAN em modo split (CU-DU separation) com orquestração via Docker Swarm. O trabalho detalha os desafios técnicos encontrados, as soluções implementadas e um guia prático para reprodução e operação do sistema.

**Palavras-chave**: 5G, srsRAN, Docker Swarm, CU-DU Split, Open5GS, ZMQ, F1-C, Network Slicing

---

## 1. Introdução

### 1.1 Contexto e Motivação

A arquitetura 5G introduziu o conceito de disagregação funcional da RAN (Radio Access Network), permitindo a separação entre a Central Unit (CU) e a Distributed Unit (DU). Esta separação oferece diversos benefícios:

- **Flexibilidade de deployment**: CU e DU podem ser implantados em locais diferentes
- **Escalabilidade**: Múltiplos DUs podem conectar-se a uma única CU
- **Eficiência de recursos**: Centralização de funções de controle
- **Cloud-native deployment**: Facilitação da virtualização de funções de rede

### 1.2 Objetivos

Este trabalho teve como objetivos:

1. Implementar uma arquitetura 5G SA funcional utilizando srsRAN em modo split
2. Containerizar os componentes CU e DU utilizando Docker
3. Orquestrar o deployment utilizando Docker Swarm
4. Estabelecer conectividade end-to-end entre UE e Core 5G
5. Documentar todos os desafios técnicos e suas soluções

---

## 2. Arquitetura do Sistema

### 2.1 Visão Geral

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST MACHINE                             │
│                                                                   │
│  ┌──────────────┐          ┌─────────────────────────────────┐ │
│  │   UE (4G)    │          │      DOCKER SWARM CLUSTER       │ │
│  │              │          │                                 │ │
│  │  Namespace   │  ZMQ     │  ┌──────────┐   ┌──────────┐  │ │
│  │    ue1       │◄────────►│  │    DU    │   │    CU    │  │ │
│  │              │ 2000/2001│  │ (Swarm)  │   │ (Swarm)  │  │ │
│  │ 10.45.1.2    │          │  │          │   │          │  │ │
│  └──────────────┘          │  │          │   │          │  │ │
│         │                  │  └────┬─────┘   └─────┬────┘  │ │
│         │                  │       │               │        │ │
│    ┌────▼────┐             │       │  F1-C/F1-U   │        │ │
│    │  veth   │             │       │  (SCTP/UDP)  │        │ │
│    │  pair   │             │       └───────┬───────┘        │ │
│    │         │             │               │                 │ │
│    └────┬────┘             │       ┌───────▼────────┐       │ │
│         │                  │       │   5GC (Open5GS)│       │ │
│    ┌────▼────┐             │       │   Docker       │       │ │
│    │ ogstun  │◄────────────┼───────┤   Compose      │       │ │
│    │10.45.0.1│             │       │                │       │ │
│    └─────────┘             │       │ N2/N3/SBI      │       │ │
│                            │       └────────────────┘       │ │
│                            └─────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                          Internet
```

### 2.2 Componentes da Arquitetura

#### 2.2.1 UE (User Equipment)
- **Software**: srsRAN UE (versão 4G/NR)
- **Interface RF**: ZMQ (Zero Message Queue) - Simulação RF via IPC
- **Namespace**: Isolado em namespace Linux `ue1`
- **IP**: 10.45.1.2/24 (atribuído dinamicamente pelo core)
- **Conectividade**: Interface `tun_srsue` + veth pair para roteamento

#### 2.2.2 DU (Distributed Unit)
- **Software**: srsRAN gNB em modo DU
- **Containerização**: Docker image `guilhermemaciel75/ud:v0.0.6`
- **Orquestração**: Docker Swarm service (`oran_du`)
- **Interfaces**:
  - **RF (ZMQ)**: 
    - TX: Bind em `tcp://*:2000` (host mode)
    - RX: Connect para `tcp://10.45.0.1:2001`
  - **F1-C**: SCTP para CU (porta 38472)
  - **F1-U**: UDP para CU (porta 2152)
- **Configurações chave**:
  - E2AP desabilitado (`enable_du_e2: false`)
  - Network mode: Overlay networks (ran, f1)
  - Portas publicadas em `mode: host` para IPv4/IPv6

#### 2.2.3 CU (Central Unit)
- **Software**: srsRAN gNB em modo CU (CU-CP + CU-UP integrados)
- **Containerização**: Docker image `guilhermemaciel75/uc:v0.0.10`
- **Orquestração**: Docker Swarm service (`oran_cu`)
- **Endpoint mode**: DNS Round-Robin (`dnsrr`) para resolução direta
- **Interfaces**:
  - **F1-C**: SCTP listen em porta 38472
  - **F1-U**: UDP em porta 2152
  - **N2 (NGAP)**: SCTP para AMF (porta 38412)
  - **N3 (GTP-U)**: UDP para UPF (porta 2152)
- **Configurações chave**:
  - E2AP desabilitado (`enable_cu_e2: false`)
  - Bind addresses dinâmicos (via `envsubst`)

#### 2.2.4 5GC (5G Core Network)
- **Software**: Open5GS (containerizado)
- **Deployment**: Docker Compose
- **Componentes**:
  - AMF (Access and Mobility Management Function)
  - SMF (Session Management Function)
  - UPF (User Plane Function)
  - NRF, PCF, UDM, UDR, AUSF (funções de suporte)
- **Interface de dados**: `ogstun` (10.45.0.1/16)
- **Redes Docker**: `docker_ran`, `docker_f1`

### 2.3 Fluxo de Conectividade

```
┌────────┐          ┌────────┐          ┌────────┐          ┌────────┐
│   UE   │          │   DU   │          │   CU   │          │  5GC   │
└───┬────┘          └───┬────┘          └───┬────┘          └───┬────┘
    │                   │                   │                   │
    │  RF (ZMQ)         │                   │                   │
    │◄─────────────────►│                   │                   │
    │                   │                   │                   │
    │                   │  F1 Setup Request │                   │
    │                   │──────────────────►│                   │
    │                   │  F1 Setup Response│                   │
    │                   │◄──────────────────│                   │
    │                   │                   │                   │
    │                   │                   │   NG Setup Request│
    │                   │                   │──────────────────►│
    │                   │                   │  NG Setup Response│
    │                   │                   │◄──────────────────│
    │                   │                   │                   │
    │  PRACH            │                   │                   │
    │──────────────────►│                   │                   │
    │  RAR              │                   │                   │
    │◄──────────────────│                   │                   │
    │                   │                   │                   │
    │  RRC Setup Req    │  InitialUL RRC   │                   │
    │──────────────────►│──────────────────►│                   │
    │                   │                   │                   │
    │                   │  UE Context Setup │                   │
    │                   │◄──────────────────│                   │
    │  RRC Setup        │                   │                   │
    │◄──────────────────│◄──────────────────│                   │
    │                   │                   │                   │
    │                   │                   │  Initial UE Msg   │
    │                   │                   │──────────────────►│
    │                   │                   │                   │
    │                   │                   │  PDU Session Est. │
    │                   │                   │◄──────────────────│
    │  NAS/RRC Reconfig │                   │                   │
    │◄──────────────────│◄──────────────────│◄──────────────────│
    │                   │                   │                   │
    │  [IP: 10.45.1.2 assigned]            │                   │
    │                   │                   │                   │
    │  User Data        │  User Data (F1-U) │  User Data (N3)   │
    │◄─────────────────►│◄─────────────────►│◄─────────────────►│
    │                   │                   │                   │
```

---

## 3. Processo de Implementação

### 3.1 Configuração do Ambiente Base

#### 3.1.1 Requisitos do Sistema

**Hardware mínimo**:
- CPU: 4 cores (8 threads recomendado)
- RAM: 8 GB (16 GB recomendado)
- Disco: 20 GB livres
- Network: Interface Ethernet/WiFi com acesso à internet

**Software**:
```bash
# Sistema Operacional
Ubuntu 20.04 LTS ou superior

# Docker Engine
Docker version 24.0+
Docker Compose version 2.0+

# Docker Swarm
Modo swarm inicializado

# Ferramentas auxiliares
- iproute2
- iptables
- tcpdump
- net-tools
```

#### 3.1.2 Inicialização do Docker Swarm

```bash
# Inicializar o swarm
docker swarm init

# Verificar status
docker node ls
```

### 3.2 Criação das Redes Docker

```bash
# Criar rede para RAN (AMF e CU-CP)
docker network create \
  --driver overlay \
  --subnet 10.53.0.0/16 \
  --attachable \
  docker_ran

# Criar rede para F1 (CU e DU)
docker network create \
  --driver overlay \
  --subnet 10.54.0.0/16 \
  --attachable \
  docker_f1
```

**Características das redes**:
- **Driver overlay**: Permite comunicação entre containers em diferentes hosts Swarm
- **Attachable**: Permite que containers standalone se conectem
- **Subnets separadas**: Isolamento de tráfego por interface (N2/N3 vs F1)

### 3.3 Deployment do Core 5G (Open5GS)

**Arquivo**: `docker-compose.yml`

```yaml
version: "3.8"

services:
  5gc:
    build: ./open5gs
    container_name: open5gs_5gc
    privileged: true
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    networks:
      ran:
        ipv4_address: 10.53.1.2
    ports:
      - "9999:9999"  # WebUI
    healthcheck:
      test: ["CMD", "pgrep", "-f", "open5gs-amfd"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  ran:
    name: docker_ran
    external: true
```

**Comando de deployment**:
```bash
cd /path/to/srsRAN_split/docker
docker compose up -d 5gc

# Verificar logs
docker logs -f open5gs_5gc

# Verificar saúde
docker ps | grep 5gc
```

**Configurações importantes do Open5GS**:

1. **AMF Configuration** (`/etc/open5gs/amf.yaml`):
```yaml
amf:
  ngap:
    - addr: 10.53.1.2
      port: 38412
  plmn:
    - plmn_id:
        mcc: 001
        mnc: 01
  tai:
    - plmn_id:
        mcc: 001
        mnc: 01
      tac: 7
```

2. **SMF Configuration** (`/etc/open5gs/smf.yaml`):
```yaml
smf:
  pfcp:
    - addr: 127.0.0.5
  subnet:
    - addr: 10.45.0.0/16
      dnn: internet
```

3. **UPF Configuration** (`/etc/open5gs/upf.yaml`):
```yaml
upf:
  pfcp:
    - addr: 127.0.0.7
  gtpu:
    - addr: 10.53.1.2
  subnet:
    - addr: 10.45.0.0/16
      dnn: internet
```

### 3.4 Build e Deployment da CU

#### 3.4.1 Estrutura de Arquivos

```
docker/cu/
├── Dockerfile
├── cu.template.yml
├── srscu (binário)
└── README.md
```

#### 3.4.2 Dockerfile da CU

```dockerfile
ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS cu

RUN apt-get clean && apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y software-properties-common gettext && \
    apt-get install -y cmake make gcc g++ pkg-config libfftw3-dev \
                       libmbedtls-dev libsctp-dev libyaml-cpp-dev \
                       libgtest-dev iproute2 && \
    apt-get update -y && \
    rm -rf /var/lib/apt/lists/*

RUN touch /tmp/cu.log

WORKDIR /cu
COPY . ./

RUN chmod +x /cu/srscu

CMD ["/bin/sh", "-c", "CU_RAN_IP=$(ip addr show dev eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) && CU_F1_IP=$(ip addr show dev eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1) && export CU_CP_BIND_ADDR=$CU_RAN_IP && export F1_BIND_ADDR=$CU_F1_IP && envsubst < /cu/cu.template.yml > /cu/cu.yml && /cu/srscu -c /cu/cu.yml & tail -f /tmp/cu.log"]
```

**Explicação**:
- **envsubst**: Substitui variáveis de ambiente no template YAML
- **Dynamic IP detection**: Obtém IPs das interfaces Docker automaticamente
- **Dual network binding**: eth0 (f1), eth1 (ran)

#### 3.4.3 Configuração da CU (cu.template.yml)

```yaml
cu_cp:
  amf:
    addr: $AMF_ADDR
    port: 38412
    bind_addr: $CU_CP_BIND_ADDR
    supported_tracking_areas:
      - tac: 7
        plmn_list:
          - plmn: "00101"
            tai_slice_support_list:
              - sst: 1
  inactivity_timer: 7200

  f1ap:
    bind_addr: $F1_BIND_ADDR

cu_up:
  nru:
    bind_addr: $F1_BIND_ADDR

log:
  filename: /tmp/cu.log
  all_level: info

pcap:
  ngap_enable: false
  ngap_filename: /tmp/cu_ngap.pcap

e2:
  enable_cu_e2: false
  addr: 127.0.0.1
  port: 36421
  bind_addr: 127.0.0.1
```

**Pontos críticos**:
- **E2AP desabilitado**: Evita timeout de 5-6 minutos tentando conectar ao RIC
- **Bind addresses dinâmicos**: Adaptam-se ao IP atribuído pelo Swarm
- **TAC e PLMN**: Devem corresponder aos configurados no AMF

#### 3.4.4 Docker Stack da CU

**Arquivo**: `cu-ran-stack.yml`

```yaml
version: "3.8"

services:
  cu:
    image: guilhermemaciel75/uc:v0.0.10
    networks:
      ran:
        aliases:
          - cu_ran
      f1:
        aliases:
          - cu_f1
    environment:
      AMF_ADDR: "10.53.1.2"
      CU_CP_BIND_ADDR: "0.0.0.0"
      F1_BIND_ADDR: "0.0.0.0"
    deploy:
      replicas: 1
      endpoint_mode: dnsrr  # DNS Round-Robin
      restart_policy:
        condition: on-failure

networks:
  ran:
    external: true
    name: "docker_ran"

  f1:
    external: true
    name: "docker_f1"
```

**Decisões de design**:
- **endpoint_mode: dnsrr**: Desabilita o VIP do Swarm, DNS resolve diretamente para IPs dos containers
- **Sem portas publicadas**: Comunicação interna via overlay networks
- **Aliases**: Facilitam descoberta de serviço (`cu_ran`, `cu_f1`)

**Deployment**:
```bash
# Build da imagem
cd docker/cu
docker build -t guilhermemaciel75/uc:v0.0.10 .

# Push para registry (opcional)
docker push guilhermemaciel75/uc:v0.0.10

# Deploy no Swarm
cd ..
docker stack deploy -c cu-ran-stack.yml oran_cu

# Verificar
docker service ls | grep oran_cu
docker service logs oran_cu_cu
```

### 3.5 Build e Deployment da DU

#### 3.5.1 Dockerfile da DU

```dockerfile
ARG OS_VERSION=24.04
FROM ubuntu:$OS_VERSION AS du

RUN apt-get clean && apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y software-properties-common gettext && \
    apt-get install -y cmake make gcc g++ pkg-config libfftw3-dev \
                       libmbedtls-dev libsctp-dev libyaml-cpp-dev \
                       libgtest-dev libzmq3-dev iproute2 && \
    apt-get update -y && \
    rm -rf /var/lib/apt/lists/*

RUN touch /tmp/du.log

WORKDIR /du
COPY . ./

RUN chmod +x /du/srsdu

CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]
```

#### 3.5.2 Configuração da DU (du.template.yml)

```yaml
gnb_id: 1

ru_sdr:
  device_driver: zmq
  device_args: tx_port=tcp://*:2000,rx_port=tcp://$RU_SDR_RX_PORT:2001,base_srate=11.52e6
  srate: 11.52
  tx_gain: 75
  rx_gain: 75

cell_cfg:
  dl_arfcn: 368500
  band: 3
  channel_bandwidth_MHz: 20
  common_scs: 15
  plmn: "00101"
  tac: 7

log:
  filename: /tmp/du.log
  all_level: info

f1ap_cu_cp_addr: $F1AP_CU_CP_ADDR
f1ap_bind_addr: $F1AP_BIND_ADDR

e2:
  enable_du_e2: false
  addr: 10.0.2.10
  bind_addr: $E2_BIND_ADDR
  port: 36421
  e2sm_kpm_enabled: false
  e2sm_rc_enabled: false
```

**Configurações ZMQ críticas**:
- **tx_port=tcp://*:2000**: Bind (servidor) na porta 2000 para transmitir ao UE
- **rx_port=tcp://10.45.0.1:2001**: Connect (cliente) à porta 2001 do UE
- **Inversão de papéis**: DU é servidor TX, cliente RX; UE é cliente TX, servidor RX
- **Base sample rate**: 11.52 MHz (compatível com LTE/5G NR)

#### 3.5.3 Docker Stack da DU

**Arquivo**: `du-ran-stack.yml`

```yaml
version: "3.8"

services:  
  du:
    image: guilhermemaciel75/ud:v0.0.6
    ports:
      - target: 36421
        published: 36421
        protocol: tcp
        mode: host
      - target: 2000
        published: 2000
        protocol: tcp
        mode: host
    networks:
      ran:
        aliases:
          - du_ran
      f1:
        aliases:
          - du_f1

    environment:
      E2_BIND_ADDR: "0.0.0.0" 
      F1AP_BIND_ADDR: "0.0.0.0"
      RU_SDR_TX_PORT: "10.45.0.1"
      RU_SDR_RX_PORT: "10.45.0.1"
      F1AP_CU_CP_ADDR: "oran_cu_cu"
      GNB_ID : "1"
         
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure

networks:
  ran:
    external: true
    name: "docker_ran"

  f1:
    external: true
    name: "docker_f1"
```

**Pontos de atenção**:
- **mode: host**: Necessário para portas ZMQ serem acessíveis em IPv4 pelo host
- **RU_SDR_RX_PORT**: IP do host (10.45.0.1) onde o UE está conectado
- **F1AP_CU_CP_ADDR**: Nome do serviço CU no Swarm (resolve via DNS)

**Deployment**:
```bash
# Build
cd docker/du
docker build -t guilhermemaciel75/ud:v0.0.6 .

# Push
docker push guilhermemaciel75/ud:v0.0.6

# Deploy
cd ..
docker stack deploy -c du-ran-stack.yml oran_du

# Verificar
docker service ls | grep oran_du
docker service logs oran_du_du
```

### 3.6 Configuração do UE

#### 3.6.1 Arquivo de Configuração (ue_zmq.conf)

```ini
[rf]
freq_offset = 0
tx_gain = 50
rx_gain = 40
srate = 11.52e6
nof_antennas = 1

device_name = zmq
device_args = tx_port=tcp://*:2001,rx_port=tcp://127.0.0.1:2000,base_srate=11.52e6

[rat.eutra]
dl_earfcn = 2850
nof_carriers = 0

[rat.nr]
bands = 3
nof_carriers = 1

[pcap]
enable = none
mac_filename = /tmp/ue_mac.pcap
mac_nr_filename = /tmp/ue_mac_nr.pcap
nas_filename = /tmp/ue_nas.pcap

[log]
all_level = info
phy_lib_level = none
all_hex_limit = 32
filename = /tmp/ue.log
file_max_size = -1

[usim]
mode = soft
algo = milenage
opc  = 63BFA50EE6523365FF14C1F45F88737D
k    = 00112233445566778899aabbccddeeff
imsi = 001010123456780
imei = 353490069873319

[rrc]
release = 15
ue_category = 4

[nas]
apn = srsapn
apn_protocol = ipv4

[gw]
netns = ue1
ip_devname = tun_srsue
ip_netmask = 255.255.255.0

[gui]
enable = false
```

**Credenciais USIM**:
- **IMSI**: 001010123456780 (deve estar cadastrado no HSS/UDM do Open5GS)
- **K**: Chave de autenticação
- **OPC**: Operator code derivado
- **Algoritmo**: Milenage (padrão 3GPP)

#### 3.6.2 Cadastro do UE no Core

**Método 1: WebUI do Open5GS**

1. Acessar: `http://localhost:9999`
2. Login: admin / 1423
3. Subscribers → New Subscriber
4. Preencher:
   - IMSI: 001010123456780
   - K: 00112233445566778899aabbccddeeff
   - OPC: 63BFA50EE6523365FF14C1F45F88737D
   - APN: srsapn

**Método 2: MongoDB direto**

```bash
docker exec -it open5gs_5gc bash

# Conectar ao MongoDB
mongo mongodb://localhost:27017/open5gs

# Inserir subscriber
db.subscribers.insert({
  "imsi" : "001010123456780",
  "security" : {
    "k" : "00112233445566778899aabbccddeeff",
    "opc" : "63BFA50EE6523365FF14C1F45F88737D",
    "amf" : "8000",
    "sqn" : NumberLong("0")
  },
  "ambr" : {
    "downlink" : { "value" : 1, "unit" : 3 },
    "uplink" : { "value" : 1, "unit" : 3 }
  },
  "slice" : [{
    "sst" : 1,
    "default_indicator" : true,
    "session" : [{
      "name" : "srsapn",
      "type" : 3,
      "ambr" : {
        "downlink" : { "value" : 1, "unit" : 3 },
        "uplink" : { "value" : 1, "unit" : 3 }
      },
      "qos" : {
        "index" : 9,
        "arp" : {
          "priority_level" : 8,
          "pre_emption_capability" : 1,
          "pre_emption_vulnerability" : 1
        }
      }
    }]
  }]
});
```

#### 3.6.3 Criação do Namespace de Rede

O UE opera em um namespace isolado para segurança e organização:

```bash
# Criar namespace
sudo ip netns add ue1

# Criar veth pair (bridge entre host e namespace)
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns ue1

# Configurar IPs
sudo ip addr add 10.45.254.1/30 dev veth0
sudo ip link set veth0 up

sudo ip netns exec ue1 ip addr add 10.45.254.2/30 dev veth1
sudo ip netns exec ue1 ip link set veth1 up
sudo ip netns exec ue1 ip link set lo up

# Configurar roteamento
sudo ip netns exec ue1 ip route add default via 10.45.254.1 dev veth1

# Habilitar IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Configurar NAT/Firewall
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 -o ogstun -j MASQUERADE
sudo iptables -A FORWARD -i veth0 -o ogstun -j ACCEPT
sudo iptables -A FORWARD -i ogstun -o veth0 -j ACCEPT
```

**Diagrama do namespace**:
```
┌─────────────────────────┐         ┌──────────────────────────┐
│   Host Network NS       │         │    ue1 Network NS        │
│                         │         │                          │
│  ┌──────────┐           │         │           ┌──────────┐  │
│  │  veth0   │           │         │           │  veth1   │  │
│  │10.45.254.1│◄─────────┼─────────┼──────────►│10.45.254.2│ │
│  └──────────┘           │         │           └──────────┘  │
│       │                 │         │                │         │
│  ┌────▼─────┐           │         │           ┌────▼─────┐  │
│  │  ogstun  │           │         │           │ tun_srsue│  │
│  │10.45.0.1 │           │         │           │10.45.1.2 │  │
│  └──────────┘           │         │           └──────────┘  │
└─────────────────────────┘         └──────────────────────────┘
```

#### 3.6.4 Execução do UE

```bash
# Navegar para o diretório
cd /path/to/srsRAN_4G/build/srsue/src

# Executar com sudo (necessário para criar interface TUN)
sudo ./srsue ue_zmq.conf
```

**Logs esperados (sucesso)**:
```
Active RF plugins: libsrsran_rf_zmq.so
Reading configuration file ue_zmq.conf...
Built in Release mode using commit ec29b0c1f on branch master.
Opening 1 channels in RF device=zmq with args=...
Current sample rate is 11.52 MHz with a base rate of 11.52 MHz
Waiting PHY to initialize ... done!
Attaching UE...
Random Access Transmission: prach_occasion=0, preamble_index=0, ra-rnti=0x39, tti=334
Random Access Complete.     c-rnti=0x4601, ta=0
RRC Connected
RRC NR reconfiguration successful.
PDU Session Establishment successful. IP: 10.45.1.2
```

---

## 4. Desafios Técnicos e Soluções

### 4.1 Problema: DU Container Exiting com Código 137

**Sintoma**:
```bash
$ docker ps -a | grep du
CONTAINER ID   STATUS
f81c365a2f24   Exited (137) 1 minute ago
```

**Análise**:
- Código 137 = 128 + 9 (SIGKILL)
- Container foi morto pelo OOM Killer ou por falha de binding

**Logs investigados**:
```bash
$ docker logs f81c365a2f24
Failed to bind SCTP socket to 10.0.2.3:0. Cause: Cannot assign requested address
```

**Causa raiz**:
O DU estava tentando fazer bind em `10.0.2.3` (IP da rede E2 RIC) que não existia no container. Isso ocorria porque:
1. A configuração E2 estava habilitada por padrão
2. O container não tinha a rede `oran-sc-ric_ric_network` conectada

**Solução**:
Desabilitar E2AP no DU editando `du.template.yml`:

```yaml
e2:
  enable_du_e2: false
  e2sm_kpm_enabled: false
  e2sm_rc_enabled: false
```

**Resultado**: DU inicia normalmente sem tentar conectar ao RIC inexistente.

---

### 4.2 Problema: UE Não Conecta ao DU (ZMQ Port Mismatch)

**Sintoma**:
```
UE: Error: connecting receiver socket: Invalid argument
DU: [zmq:tx:0:0] Waiting for request. (nenhum dado recebido)
```

**Análise**:
O ZMQ opera em modo socket TCP com papéis cliente/servidor invertidos:
- **DU TX** → **UE RX**: DU é servidor (bind), UE é cliente (connect)
- **UE TX** → **DU RX**: UE é servidor (bind), DU é cliente (connect)

**Investigação**:

1. Verificar porta escutando no DU:
```bash
$ docker exec <du_container> ss -tuln | grep 2000
tcp   LISTEN   0.0.0.0:2000    0.0.0.0:*
```

2. Verificar configuração ZMQ do UE:
```ini
[rf]
device_args = tx_port=tcp://*:2001,rx_port=tcp://127.0.0.1:2000
```

**Problema identificado**:
- UE tentando conectar em `127.0.0.1:2000` (localhost)
- DU escutando em IP do container Docker (não acessível de fora)

**Soluções testadas**:

**Tentativa 1**: `network_mode: host` no DU
```yaml
services:
  du:
    network_mode: host
```
❌ **Falha**: Docker Swarm não suporta `network_mode: host` para serviços replicados.

**Tentativa 2**: Publicar porta com `mode: ingress` (padrão)
```yaml
ports:
  - "2000:2000"
```
❌ **Falha parcial**: Swarm publicou apenas em IPv6 (`:::2000`), UE tentando IPv4.

**Solução final**: Publicar porta com `mode: host` explicitamente
```yaml
ports:
  - target: 2000
    published: 2000
    protocol: tcp
    mode: host
```

Verificação:
```bash
$ ss -tuln | grep 2000
tcp   LISTEN   0.0.0.0:2000    0.0.0.0:*    # IPv4 ✓
tcp   LISTEN   :::2000         :::*          # IPv6 ✓
```

✅ **Sucesso**: UE agora consegue conectar à porta 2000 do host, que encaminha para o DU.

---

### 4.3 Problema: DU Trava Após "Task Worker Radio Started"

**Sintoma**:
```
2025-11-11T19:13:13.543066 [zmq:tx:0:0] [I] Waiting for request.
2025-11-11T19:13:13.543080 [zmq:rx:0:0] [I] Waiting for data.
[... aguarda 5-6 minutos sem progresso ...]
```

**Análise**:
O DU aparentava travar após inicializar o worker de rádio, sem processar mensagens ZMQ.

**Investigação profunda**:

1. Verificar ordem de inicialização:
```bash
$ docker logs <du> | grep -E "started|Starting"
[DU      ] [I] Starting DU...
[RADIO   ] [I] Task worker "radio" started
[SCTP-GW ] [I] E2AP: Bind to 127.0.0.1:0 was successful
# Trava aqui por ~6 minutos
```

2. Tcpdump na interface E2:
```bash
$ docker exec <du> tcpdump -i any port 36421 -n
... attempting connection to 10.0.2.10:36421 ...
... SYN retransmissions ...
... timeout after 360 seconds
```

**Causa raiz**: 
O DU estava tentando conectar ao Near-RT RIC (interface E2) em `10.0.2.10:36421` com timeout padrão de 6 minutos. Durante esse tempo, o thread principal ficava bloqueado.

**Solução**:
Desabilitar completamente E2 no DU:

```yaml
e2:
  enable_du_e2: false
  addr: 10.0.2.10
  bind_addr: $E2_BIND_ADDR
  port: 36421
  e2sm_kpm_enabled: false
  e2sm_rc_enabled: false
```

✅ **Resultado**: DU inicia em ~2 segundos e processa mensagens ZMQ imediatamente.

---

### 4.4 Problema: CU Com Parsing Error de E2 Configuration

**Sintoma**:
```
INI was not able to parse e2.enable_cu_cp_e2
Run with --help for more information.
```

**Análise**:
A versão do srsRAN CU compilada não reconhecia os parâmetros `enable_cu_cp_e2` e `enable_cu_up_e2` documentados na referência mais recente.

**Investigação**:

1. Testar diferentes sintaxes:
```yaml
# Tentativa 1: Dentro de cu_cp e cu_up
cu_cp:
  e2:
    enable_cu_cp_e2: false
cu_up:
  e2:
    enable_cu_up_e2: false
```
❌ Seções não expandidas pelo envsubst

2. Verificar versão srsRAN:
```bash
$ docker exec <cu> /cu/srscu --version
Built in Release mode using commit  on branch 
```
(Versão antiga sem suporte completo a E2)

**Solução descoberta**:
A versão utilizada aceita apenas `enable_cu_e2` (sem sufixo `_cp` ou `_up`):

```yaml
e2:
  enable_cu_e2: false
  addr: 127.0.0.1
  port: 36421
  bind_addr: 127.0.0.1
```

✅ **Resultado**: CU aceita a configuração e inicia sem erros.

---

### 4.5 Problema: DU Conecta ao IP Errado da CU (VIP Stale)

**Sintoma**:
```
[DU-F1   ] [D] F1-C: Connecting to 10.54.1.19:38472...
[DU-F1   ] [I] Rx PDU du=1 tid=0: F1SetupFailure
Cause: "message-not-compatible-with-receiver-state"
```

**Análise**:
O DU conseguia conectar e recebia F1SetupFailure, mas a CU (em `10.54.1.31`) não mostrava nenhuma conexão nos logs.

**Investigação**:

1. DNS do DU:
```bash
$ docker exec <du> getent hosts oran_cu_cu
10.54.1.19      oran_cu_cu
```

2. IP real da CU:
```bash
$ docker network inspect docker_f1 | grep -A5 oran_cu
"IPv4Address": "10.54.1.31/24"
```

3. Quem está em 10.54.1.19?
```bash
$ docker network inspect docker_f1 | grep "10.54.1.19"
# Nada!
```

**Causa raiz**:
O Docker Swarm usa um **Virtual IP (VIP)** como load balancer para serviços. O VIP `10.54.1.19` estava cacheado de um deployment anterior e apontando para um endpoint inexistente ou para uma CU antiga que ainda respondia com erro.

**Soluções tentadas**:

**Tentativa 1**: Reiniciar serviços
```bash
docker service update --force oran_cu_cu
docker service update --force oran_du_du
```
❌ VIP persistiu no cache DNS

**Tentativa 2**: Remover containers antigos
```bash
docker ps -a | grep uc
docker rm -f <ids_antigos>
```
❌ VIP ainda apontando para endpoint stale

**Solução final**: Usar `endpoint_mode: dnsrr` no CU

```yaml
services:
  cu:
    deploy:
      endpoint_mode: dnsrr  # DNS Round-Robin
```

**O que muda**:
- **Antes (VIP)**: `oran_cu_cu` → VIP (10.54.1.19) → Container real
- **Depois (dnsrr)**: `oran_cu_cu` → IP do container diretamente (10.54.1.35)

**Trade-offs**:
- ✅ Sem cache stale
- ✅ DNS resolve diretamente
- ❌ Não funciona com portas publicadas (`mode: ingress`)
- ❌ Sem load balancing automático (mas OK para 1 réplica)

✅ **Resultado**: DU agora conecta ao IP correto da CU.

---

### 4.6 Problema: CU Não Mostra Logs de Conexão F1

**Sintoma**:
```
# DU logs:
[DU-F1   ] [I] Tx PDU du=1 tid=0: F1SetupRequest
[DU-F1   ] [I] Rx PDU du=1 tid=0: F1SetupResponse
[DU-F1   ] [I] F1 Setup: Procedure completed successfully.

# CU logs (stdout):
[SCTP-GW ] [I] F1-C: Listening for new SCTP connections on port 38472...
(nada mais)
```

**Análise**:
O DU reportava sucesso, mas a CU não mostrava nada em stdout.

**Investigação**:

1. Verificar escuta SCTP:
```bash
$ docker exec <cu> ss -ln | grep 38472
sctp  LISTEN  10.54.1.35:38472    0.0.0.0:*
```
✓ CU está escutando corretamente

2. Verificar arquivo de log interno:
```bash
$ docker exec <cu> cat /tmp/cu.log | tail -20
[SCTP-GW ] [I] F1-C: Listening for new SCTP connections on port 38472...
(também nada)
```

3. Tcpdump no container CU:
```bash
$ docker exec <cu> tcpdump -i any port 38472 -n
... SCTP INIT from 10.54.1.36:xxxxx ...
... SCTP INIT-ACK to 10.54.1.36:xxxxx ...
... SCTP ESTABLISHED ...
```
✓ Conexão SCTP foi estabelecida!

**Causa raiz**:
O log level `info` não estava logando mensagens de protocolo F1-C/F1-U. As mensagens eram processadas internamente mas não escritas em stdout/file.

**Solução**:
Aumentar log level ou usar monitoramento ativo:

```bash
# Monitorar logs em tempo real com grep
docker logs -f <cu_container> 2>&1 | grep -E "F1|InitialUL|UEContext"
```

Ou editar `cu.template.yml`:
```yaml
log:
  filename: /tmp/cu.log
  all_level: debug  # ou warning
  f1ap_json_enabled: true
```

✅ **Verificação final**: Com monitoramento ativo, conseguimos ver:
```
[CU-CP-F1] [I] Rx PDU du=1 tid=0: F1SetupRequest
[CU-CP-F1] [I] Tx PDU du=1 tid=0: F1SetupResponse
[CU-CP-F1] [I] Rx PDU du=1 tid=1 du_ue=0: InitialULRRCMessageTransfer
[CU-CP-F1] [I] Tx PDU du=1 ue=0: UEContextSetupRequest
```

---

### 4.7 Problema: UE Falha em Configurar Interface GW

**Sintoma**:
```
Random Access Complete.     c-rnti=0x4601, ta=0
RRC Connected
Failed to setup/configure GW interface
RRC NR reconfiguration successful.
```

**Análise**:
O UE completou attach até RRC Connected, mas falhou ao criar a interface de rede.

**Investigação**:

1. Verificar configuração GW:
```ini
[gw]
netns = ue1
ip_devname = tun_srsue
ip_netmask = 255.255.255.0
```

2. Verificar namespace:
```bash
$ sudo ip netns list
(vazio)
```

**Causa raiz**:
O namespace `ue1` não existia, e o srsUE não tem permissão para criá-lo automaticamente.

**Soluções possíveis**:

**Opção 1**: Criar namespace manualmente (RECOMENDADO)
```bash
sudo ip netns add ue1
```

**Opção 2**: Remover namespace do config (menos seguro)
```ini
[gw]
# netns = ue1  # comentar ou remover
ip_devname = tun_srsue
ip_netmask = 255.255.255.0
```

✅ **Escolha**: Opção 1 - criar namespace (melhor isolamento e segurança)

---

### 4.8 Problema: UE Sem Conectividade com Core (Namespace Isolado)

**Sintoma**:
```bash
$ sudo ip netns exec ue1 ping 10.45.1.1
ping: connect: A rede está fora de alcance
```

**Análise**:
O UE recebeu IP `10.45.1.2` mas não consegue alcançar o gateway `10.45.1.1`.

**Investigação**:

1. Verificar rotas no namespace:
```bash
$ sudo ip netns exec ue1 ip route show
10.45.1.0/24 dev tun_srsue proto kernel scope link src 10.45.1.2
```
(falta rota default)

2. Verificar interface no host:
```bash
$ ip addr show ogstun
3: ogstun: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP>
    inet 10.45.0.1/16 scope global ogstun
```
✓ `ogstun` existe no host

**Causa raiz**:
O namespace `ue1` está **isolado** da rede do host. Não há caminho de rede entre:
- `tun_srsue` (dentro de `ue1`)
- `ogstun` (na rede do host)

**Solução**: Criar veth pair como bridge

```bash
# 1. Criar par de interfaces virtuais
sudo ip link add veth0 type veth peer name veth1

# 2. Mover veth1 para namespace ue1
sudo ip link set veth1 netns ue1

# 3. Configurar IPs (rede /30 = 2 hosts)
sudo ip addr add 10.45.254.1/30 dev veth0
sudo ip link set veth0 up

sudo ip netns exec ue1 ip addr add 10.45.254.2/30 dev veth1
sudo ip netns exec ue1 ip link set veth1 up

# 4. Configurar rota default no namespace
sudo ip netns exec ue1 ip route add default via 10.45.254.1 dev veth1

# 5. Habilitar IP forwarding no host
sudo sysctl -w net.ipv4.ip_forward=1

# 6. Configurar NAT e firewall
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 -o ogstun -j MASQUERADE
sudo iptables -A FORWARD -i veth0 -o ogstun -j ACCEPT
sudo iptables -A FORWARD -i ogstun -o veth0 -j ACCEPT

# 7. Ativar loopback no namespace
sudo ip netns exec ue1 ip link set lo up
```

**Teste de conectividade**:
```bash
# Ping para gateway do veth pair
$ sudo ip netns exec ue1 ping -c 2 10.45.254.1
64 bytes from 10.45.254.1: icmp_seq=1 ttl=64 time=0.047 ms

# Ping para core 5G
$ sudo ip netns exec ue1 ping -c 2 10.45.0.1
64 bytes from 10.45.0.1: icmp_seq=1 ttl=64 time=0.034 ms
```

✅ **Sucesso**: UE agora tem conectividade completa com o core.

---

## 5. Procedimentos Operacionais

### 5.1 Startup Completo do Sistema

**Script de inicialização**:

```bash
#!/bin/bash
# startup.sh - Inicializa toda a arquitetura 5G

set -e

echo "=== 5G srsRAN Split Deployment ==="

# 1. Verificar Docker Swarm
echo "[1/7] Checking Docker Swarm..."
if ! docker info | grep -q "Swarm: active"; then
    echo "Initializing Docker Swarm..."
    docker swarm init
fi

# 2. Criar redes Docker
echo "[2/7] Creating Docker networks..."
docker network create --driver overlay --subnet 10.53.0.0/16 --attachable docker_ran 2>/dev/null || true
docker network create --driver overlay --subnet 10.54.0.0/16 --attachable docker_f1 2>/dev/null || true

# 3. Deploy 5GC
echo "[3/7] Deploying 5G Core (Open5GS)..."
cd /path/to/srsRAN_split/docker
docker compose up -d 5gc
sleep 10

# Verificar saúde do 5GC
docker ps | grep 5gc | grep healthy || {
    echo "ERROR: 5GC not healthy"
    exit 1
}

# 4. Deploy CU
echo "[4/7] Deploying CU (Central Unit)..."
docker stack deploy -c cu-ran-stack.yml oran_cu
sleep 20

# 5. Deploy DU
echo "[5/7] Deploying DU (Distributed Unit)..."
docker stack deploy -c du-ran-stack.yml oran_du
sleep 20

# 6. Verificar F1 Setup
echo "[6/7] Verifying F1 Setup..."
DU_ID=$(docker ps -q --filter "name=oran_du")
if docker logs $DU_ID 2>&1 | grep -q "F1 Setup: Procedure completed successfully"; then
    echo "✓ F1 Setup successful"
else
    echo "✗ F1 Setup failed"
    exit 1
fi

# 7. Configurar namespace do UE
echo "[7/7] Setting up UE namespace..."
sudo ip netns add ue1 2>/dev/null || true
sudo ip link add veth0 type veth peer name veth1 2>/dev/null || true
sudo ip link set veth1 netns ue1
sudo ip addr add 10.45.254.1/30 dev veth0 2>/dev/null || true
sudo ip link set veth0 up
sudo ip netns exec ue1 ip addr add 10.45.254.2/30 dev veth1 2>/dev/null || true
sudo ip netns exec ue1 ip link set veth1 up
sudo ip netns exec ue1 ip link set lo up
sudo ip netns exec ue1 ip route add default via 10.45.254.1 dev veth1 2>/dev/null || true
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
sudo iptables -t nat -C POSTROUTING -s 10.45.0.0/16 -o ogstun -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 -o ogstun -j MASQUERADE
sudo iptables -C FORWARD -i veth0 -o ogstun -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i veth0 -o ogstun -j ACCEPT
sudo iptables -C FORWARD -i ogstun -o veth0 -j ACCEPT 2>/dev/null || \
    sudo iptables -A FORWARD -i ogstun -o veth0 -j ACCEPT

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Status:"
docker service ls | grep oran
echo ""
echo "To run UE:"
echo "  cd /path/to/srsRAN_4G/build/srsue/src"
echo "  sudo ./srsue ue_zmq.conf"
echo ""
```

**Uso**:
```bash
chmod +x startup.sh
./startup.sh
```

### 5.2 Shutdown e Cleanup

**Script de desligamento**:

```bash
#!/bin/bash
# shutdown.sh - Para e limpa toda a arquitetura

set -e

echo "=== 5G srsRAN Split Shutdown ==="

# 1. Parar serviços Swarm
echo "[1/5] Stopping Swarm services..."
docker stack rm oran_du
docker stack rm oran_cu
sleep 10

# 2. Parar 5GC
echo "[2/5] Stopping 5G Core..."
cd /path/to/srsRAN_split/docker
docker compose down

# 3. Remover namespace UE
echo "[3/5] Cleaning up UE namespace..."
sudo ip netns exec ue1 ip link set veth1 down 2>/dev/null || true
sudo ip link del veth0 2>/dev/null || true
sudo ip netns del ue1 2>/dev/null || true

# 4. Limpar regras iptables
echo "[4/5] Cleaning iptables rules..."
sudo iptables -t nat -D POSTROUTING -s 10.45.0.0/16 -o ogstun -j MASQUERADE 2>/dev/null || true
sudo iptables -D FORWARD -i veth0 -o ogstun -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -i ogstun -o veth0 -j ACCEPT 2>/dev/null || true

# 5. (Opcional) Remover redes Docker
echo "[5/5] Removing Docker networks..."
read -p "Remove Docker networks? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker network rm docker_ran docker_f1 2>/dev/null || true
fi

echo "=== Shutdown Complete ==="
```

### 5.3 Monitoramento em Tempo Real

#### 5.3.1 Visualizando Métricas Interativas do DU

O srsRAN DU possui um **console interativo** que permite visualizar métricas em tempo real. Para acessá-lo no container Docker:

**Método 1: Attach ao processo do DU (RECOMENDADO)**

```bash
# Encontrar o container DU
DU_CONTAINER=$(docker ps -q --filter "name=oran_du" | head -1)

# Attach ao processo do srsdu (mantém o console interativo)
docker attach $DU_CONTAINER
```

**Comandos disponíveis no console**:
- `t` ou `T`: Toggle métricas de throughput e PHY
- `h`: Mostrar help com todos os comandos
- `Ctrl+P` seguido de `Ctrl+Q`: Sair sem parar o container

**Exemplo de métricas visualizadas**:
```
       |--------------------DL---------------------|-------------------------UL------------------------------
pci rnti | cqi  ri  mcs  brate   ok  nok  (%)  dl_bs | pusch  rsrp  mcs  brate   ok  nok  (%)    bsr     ta  phr
  1 4601 |  15 1.0   27   686k  119    0   0%      0 |  32.7 -12.4   28   236k   44    0   0%      0   -56n   17
```

**Significado das colunas**:
- **pci**: Physical Cell ID
- **rnti**: Radio Network Temporary Identifier do UE
- **cqi**: Channel Quality Indicator (0-15, maior = melhor)
- **ri**: Rank Indicator (número de streams MIMO)
- **mcs**: Modulation and Coding Scheme (0-28, maior = maior throughput)
- **brate**: Bitrate (DL/UL)
- **ok/nok**: Blocos transmitidos com sucesso/erro
- **pusch**: PUSCH SNR (dB)
- **rsrp**: Reference Signal Received Power (dBm)
- **bsr**: Buffer Status Report (dados pendentes no UE)
- **ta**: Timing Advance
- **phr**: Power Headroom Report (dB)

**Método 2: Exec interativo (se attach não funcionar)**

```bash
# Executar shell interativo no container
docker exec -it $DU_CONTAINER /bin/bash

# Dentro do container, localizar o processo
ps aux | grep srsdu

# Conectar ao console via tmux/screen (se disponível)
# Ou visualizar logs em /tmp/du.log
tail -f /tmp/du.log
```

**Método 3: Modificar Dockerfile para Console Interativo Direto** ⭐⭐

**IMPORTANTE**: O Dockerfile original roda o DU em background (`&`), o que impede acesso ao console interativo. Para corrigir:

**Passo 1**: Editar `du/Dockerfile` (linha do CMD):

```dockerfile
# Versão ORIGINAL (não permite console interativo):
#CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]

# Versão CORRIGIDA (console interativo funciona):
CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && exec /du/srsdu -c /du/du.yml"]
```

**Mudanças**:
- Removido `&` (não roda em background)
- Removido `tail -f /tmp/du.log`
- Adicionado `exec` (substitui o shell pelo processo srsdu)

**Passo 2**: Rebuild e redeploy

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker

# Usar o script automatizado
chmod +x rebuild_du_interactive.sh
./rebuild_du_interactive.sh

# OU fazer manualmente:
# 1. Parar serviço
docker service rm oran_du_du

# 2. Rebuild
cd du
docker build -t guilhermemaciel75/ud:v0.0.7-interactive .

# 3. Push (opcional)
docker push guilhermemaciel75/ud:v0.0.7-interactive

# 4. Atualizar image no du-ran-stack.yml
# image: guilhermemaciel75/ud:v0.0.7-interactive

# 5. Redeploy
cd ..
docker stack deploy -c du-ran-stack.yml oran_du
```

**Passo 3**: Aguardar inicialização e conectar

```bash
# Aguardar ~20 segundos
sleep 20

# Encontrar container
DU_CONTAINER=$(docker ps -q --filter "name=oran_du" | head -1)

# Conectar ao console
docker attach $DU_CONTAINER
```

Agora você pode pressionar `t` ou `T` e verá as métricas em tempo real! 🎉

**Trade-offs desta solução**:
- ✅ Console interativo funciona perfeitamente
- ✅ Pode ver métricas pressionando `t`
- ❌ Logs não vão mais para `/tmp/du.log` (vão para stdout)
- ❌ `docker logs` mostrará MUITO mais informação (pode ser pesado)

**Alternativa**: Se preferir manter logs em arquivo E ter console interativo, use socat:

```dockerfile
# Instalar socat
RUN apt-get update && apt-get install -y socat

# CMD com socat (acesso via telnet)
CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && mkfifo /tmp/console_in /tmp/console_out && (socat TCP-LISTEN:5555,reuseaddr,fork SYSTEM:'cat > /tmp/console_in; cat /tmp/console_out' &) && /du/srsdu -c /du/du.yml < /tmp/console_in > /tmp/console_out 2>&1 | tee /tmp/du.log"]
```

Depois, publique a porta 5555 no `du-ran-stack.yml`:
```yaml
ports:
  - target: 5555
    published: 5555
    protocol: tcp
    mode: host
```

E conecte via:
```bash
telnet localhost 5555
# Agora pode pressionar 't' para ver métricas
```

#### 5.3.2 Script de Monitoramento Geral

**Script de monitoramento de logs**:

```bash
#!/bin/bash
# monitor.sh - Monitora logs de todos os componentes

# Função para monitorar componente
monitor_component() {
    local name=$1
    local filter=$2
    local container=$3
    
    echo "=== $name Logs ==="
    docker logs -f $container 2>&1 | grep --line-buffered -E "$filter" | while read line; do
        echo "[$(date '+%H:%M:%S')] [$name] $line"
    done &
}

# Pegar IDs dos containers
CU_ID=$(docker ps -q --filter "name=oran_cu")
DU_ID=$(docker ps -q --filter "name=oran_du")
GC_ID=$(docker ps -q --filter "name=5gc")

# Monitorar cada componente
monitor_component "CU" "F1|InitialUL|UEContext|NGSetup|error" $CU_ID
monitor_component "DU" "F1|PRACH|ZMQ|error" $DU_ID
monitor_component "5GC" "AMF|SMF|UPF|error|PDU" $GC_ID

# Aguardar Ctrl+C
wait
```

**Uso**:
```bash
./monitor.sh
```

**Saída esperada** (attach bem-sucedido):
```
[19:51:30] [DU] PRACH detected: preamble=0 ta=0.00us
[19:51:30] [DU] Tx PDU: InitialULRRCMessageTransfer
[19:51:30] [CU] Rx PDU: InitialULRRCMessageTransfer
[19:51:30] [CU] Tx PDU: UEContextSetupRequest
[19:51:30] [DU] Rx PDU: UEContextSetupResponse
[19:51:31] [5GC] [AMF] Initial UE Message received
[19:51:31] [5GC] [SMF] PDU Session Establishment Request
[19:51:31] [5GC] [UPF] GTP-U tunnel created: TEID=0x12345678
[19:51:31] [CU] Tx PDU: UEContextModificationRequest
```

### 5.4 Health Checks

**Script de verificação**:

```bash
#!/bin/bash
# healthcheck.sh - Verifica saúde de todos os componentes

check_service() {
    local name=$1
    local check_cmd=$2
    
    printf "%-20s " "$name:"
    if eval $check_cmd > /dev/null 2>&1; then
        echo "✓ OK"
        return 0
    else
        echo "✗ FAILED"
        return 1
    fi
}

echo "=== System Health Check ==="
echo ""

# Docker Swarm
check_service "Docker Swarm" "docker info | grep -q 'Swarm: active'"

# Redes Docker
check_service "Network: docker_ran" "docker network inspect docker_ran"
check_service "Network: docker_f1" "docker network inspect docker_f1"

# 5GC
check_service "5G Core (5gc)" "docker ps | grep -q '5gc.*healthy'"

# CU
CU_ID=$(docker ps -q --filter "name=oran_cu" | head -1)
if [ -n "$CU_ID" ]; then
    check_service "CU Container" "docker inspect -f '{{.State.Running}}' $CU_ID | grep -q true"
    check_service "CU NG Setup" "docker logs $CU_ID 2>&1 | grep -q 'Connected to AMF'"
    check_service "CU F1 Listen" "docker exec $CU_ID ss -ln | grep -q '38472'"
else
    printf "%-20s ✗ FAILED (not found)\n" "CU Container"
fi

# DU
DU_ID=$(docker ps -q --filter "name=oran_du" | head -1)
if [ -n "$DU_ID" ]; then
    check_service "DU Container" "docker inspect -f '{{.State.Running}}' $DU_ID | grep -q true"
    check_service "DU F1 Setup" "docker logs $DU_ID 2>&1 | grep -q 'F1 Setup: Procedure completed successfully'"
    check_service "DU ZMQ Listen" "ss -ln | grep -q '0.0.0.0:2000'"
else
    printf "%-20s ✗ FAILED (not found)\n" "DU Container"
fi

# UE Namespace
check_service "UE Namespace" "sudo ip netns list | grep -q ue1"
check_service "UE veth pair" "ip link show veth0"
check_service "UE Gateway route" "sudo ip netns exec ue1 ip route | grep -q default"

echo ""
echo "=== Connectivity Tests ==="
echo ""

# Teste de ping (se UE estiver rodando)
if sudo ip netns exec ue1 ip addr show tun_srsue 2>/dev/null | grep -q inet; then
    UE_IP=$(sudo ip netns exec ue1 ip addr show tun_srsue | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    echo "UE IP: $UE_IP"
    
    check_service "UE → veth gateway" "sudo ip netns exec ue1 ping -c 1 -W 1 10.45.254.1"
    check_service "UE → 5GC gateway" "sudo ip netns exec ue1 ping -c 1 -W 1 10.45.0.1"
else
    echo "UE not attached (tun_srsue not found)"
fi
```

**Uso**:
```bash
./healthcheck.sh
```

**Saída esperada** (sistema saudável):
```
=== System Health Check ===

Docker Swarm         : ✓ OK
Network: docker_ran  : ✓ OK
Network: docker_f1   : ✓ OK
5G Core (5gc)        : ✓ OK
CU Container         : ✓ OK
CU NG Setup          : ✓ OK
CU F1 Listen         : ✓ OK
DU Container         : ✓ OK
DU F1 Setup          : ✓ OK
DU ZMQ Listen        : ✓ OK
UE Namespace         : ✓ OK
UE veth pair         : ✓ OK
UE Gateway route     : ✓ OK

=== Connectivity Tests ===

UE IP: 10.45.1.2
UE → veth gateway    : ✓ OK
UE → 5GC gateway     : ✓ OK
```

---

## 6. Troubleshooting Guide

### 6.1 Matriz de Problemas Comuns

| **Sintoma** | **Causa Provável** | **Diagnóstico** | **Solução** |
|-------------|-------------------|-----------------|-------------|
| Container DU exit 137 | E2 binding falhou | `docker logs <du>` | Desabilitar E2: `enable_du_e2: false` |
| UE: "Error connecting socket" | ZMQ port mismatch | `ss -tuln \| grep 2000` | Publicar porta com `mode: host` |
| DU trava após "radio started" | E2 timeout (6 min) | `docker logs <du>` aguardar | Desabilitar E2: `enable_du_e2: false` |
| CU: "INI parse error e2" | Parâmetro E2 inválido | `docker logs <cu>` | Usar `enable_cu_e2` (sem `_cp/_up`) |
| F1 Setup Failure | DU→CU IP errado | `getent hosts oran_cu_cu` | `endpoint_mode: dnsrr` na CU |
| CU não mostra logs F1 | Log level baixo | Testar com `grep` ativo | `f1ap_json_enabled: true` ou debug |
| UE: "Failed setup GW" | Namespace inexistente | `ip netns list` | `sudo ip netns add ue1` |
| UE: ping não funciona | Namespace isolado | `ip netns exec ue1 ip route` | Criar veth pair + NAT |
| NG Setup falha | AMF IP errado | `docker logs <cu>` | Verificar `AMF_ADDR=10.53.1.2` |
| No PRACH detection | ZMQ não conectado | `docker logs <du> \| grep zmq` | Verificar UE rodando + porta 2000 |

### 6.2 Comandos de Diagnóstico Rápido

**Verificar estado dos serviços**:
```bash
# Swarm services
docker service ls

# Containers rodando
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Logs condensados
docker service logs --tail 50 oran_cu_cu
docker service logs --tail 50 oran_du_du
```

**Verificar conectividade de rede**:
```bash
# Redes Swarm
docker network inspect docker_f1 --format '{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{"\n"}}{{end}}'

# Portas escutando
ss -tuln | grep -E "2000|38472|38412"

# DNS resolution dentro do DU
docker exec $(docker ps -q --filter name=oran_du) getent hosts oran_cu_cu
```

**Verificar ZMQ**:
```bash
# DU: deve mostrar bind em 2000
docker exec $(docker ps -q --filter name=oran_du) ss -tuln | grep 2000

# Host: deve mostrar 0.0.0.0:2000 (IPv4)
ss -tuln | grep 2000
```

**Verificar F1 interface**:
```bash
# CU: deve mostrar LISTEN em 38472
docker exec $(docker ps -q --filter name=oran_cu) ss -ln | grep 38472

# DU: deve mostrar ESTAB connection
docker exec $(docker ps -q --filter name=oran_du) ss -o | grep 38472
```

**Verificar UE attach**:
```bash
# Namespace
sudo ip netns exec ue1 ip addr show

# Interface TUN
sudo ip netns exec ue1 ip addr show tun_srsue

# Rotas
sudo ip netns exec ue1 ip route show

# Conectividade
sudo ip netns exec ue1 ping -c 2 10.45.0.1
```

### 6.3 Troubleshooting Tree

```
┌─────────────────────────────────────┐
│  UE não conecta ao DU               │
└──────────┬──────────────────────────┘
           │
           ├─► UE mostra "Error connecting socket"
           │   └─► Verificar: ss -tuln | grep 2000 no host
           │       ├─► Não mostra nada → DU não publicou porta
           │       │   └─► Solução: Adicionar mode: host em du-ran-stack.yml
           │       └─► Mostra só :::2000 (IPv6) → Problema conhecido
           │           └─► Solução: Mesma acima (mode: host força IPv4)
           │
           ├─► UE conecta mas DU não detecta PRACH
           │   └─► Verificar: docker logs <du> | grep zmq
           │       ├─► "Waiting for data" forever → ZMQ RX não recebendo
           │       │   └─► Solução: Verificar RU_SDR_RX_PORT=10.45.0.1
           │       └─► Nenhuma mensagem zmq → DU travado
           │           └─► Ver: "DU trava após radio started"
           │
           └─► DU trava após "Task worker radio started"
               └─► Aguardar 6 minutos: se destravar → E2 timeout
                   └─► Solução: enable_du_e2: false no du.template.yml

┌─────────────────────────────────────┐
│  DU não conecta à CU (F1)           │
└──────────┬──────────────────────────┘
           │
           ├─► DU: "F1 Setup Failure"
           │   └─► Verificar IP: docker exec <du> getent hosts oran_cu_cu
           │       └─► IP não corresponde à CU real
           │           └─► Solução: endpoint_mode: dnsrr em cu-ran-stack.yml
           │
           ├─► DU: "SCTP connection refused"
           │   └─► CU não está escutando
           │       └─► docker exec <cu> ss -ln | grep 38472
           │           └─► Nada → CU não inicializou
           │               └─► Ver logs: docker logs <cu>
           │
           └─► DU: conexão estabelece mas CU não mostra logs
               └─► CU em modo info (não loga F1)
                   └─► Solução: Monitorar com grep ativo

┌─────────────────────────────────────┐
│  CU não conecta ao AMF              │
└──────────┬──────────────────────────┘
           │
           ├─► CU: "NG Setup Request" mas sem resposta
           │   └─► AMF não está rodando
           │       └─► docker ps | grep 5gc
           │           └─► Não healthy → docker logs open5gs_5gc
           │
           └─► CU: "SCTP connection timeout"
               └─► Rede docker_ran não configurada
                   └─► docker network inspect docker_ran
                       └─► CU não está na rede → redeployer CU

┌─────────────────────────────────────┐
│  UE attach OK mas sem conectividade │
└──────────┬──────────────────────────┘
           │
           ├─► Ping: "Network is unreachable"
           │   └─► sudo ip netns exec ue1 ip route
           │       └─► Sem rota default
           │           └─► Solução: Criar veth pair + rota default
           │
           └─► Ping para gateway funciona, internet não
               └─► Verificar NAT: sudo iptables -t nat -L -n
                   └─► Sem regra MASQUERADE
                       └─► Solução: iptables -t nat -A POSTROUTING ...
```

---

## 7. Considerações de Performance

### 7.1 Limitações do ZMQ

O ZMQ (Zero Message Queue) é uma implementação de RF simulado via IPC/TCP. **Não é adequado para produção**, apenas para desenvolvimento e testes.

**Limitações**:
- Latência alta (>1ms típico, vs <100μs em RF real)
- Jitter variável (depende de carga do sistema)
- Sem controle de potência real
- Sem efeitos de canal (fading, interferência)
- Throughput limitado pela rede (não pela banda RF)

**Alternativas para produção**:
- **USRP** (Ettus Research): SDR de alta performance
- **LimeSDR**: SDR open-source de baixo custo
- **BladeRF**: SDR mid-range

### 7.2 Otimizações de Sistema

**CPU Scaling Governor**:
```bash
# Verificar
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Definir para performance
sudo cpupower frequency-set -g performance

# Ou via sysfs
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo performance | sudo tee $cpu
done
```

**DRM KMS Polling** (reduz interrupções):
```bash
# Desabilitar
echo N | sudo tee /sys/module/drm_kms_helper/parameters/poll
```

**Network Tuning**:
```bash
# Aumentar buffers UDP (importante para F1-U e N3)
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.wmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400
sudo sysctl -w net.core.wmem_default=26214400

# Aumentar backlog
sudo sysctl -w net.core.netdev_max_backlog=10000
```

**Docker Resource Limits**:
```yaml
# Em du-ran-stack.yml e cu-ran-stack.yml
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 4G
    reservations:
      cpus: '1.0'
      memory: 2G
```

### 7.3 Métricas e KPIs

**Latência E2E** (UE → Core):
```bash
# RTT típico esperado (ZMQ)
sudo ip netns exec ue1 ping -c 100 10.45.0.1 | tail -1
# rtt min/avg/max/mdev = 0.020/0.050/0.150/0.030 ms (bom)
```

**Throughput DL/UL**:
```bash
# Instalar iperf3 no namespace
sudo ip netns exec ue1 apt install iperf3

# Servidor no core
docker exec open5gs_5gc iperf3 -s -B 10.45.0.1 &

# Cliente no UE (DL test)
sudo ip netns exec ue1 iperf3 -c 10.45.0.1 -t 30
# Throughput esperado (ZMQ): 10-50 Mbps (limitado por CPU e ZMQ overhead)
```

**Taxa de sucesso de attach**:
```bash
# Executar UE 10 vezes, contar sucessos
for i in {1..10}; do
    timeout 60 sudo ./srsue ue_zmq.conf 2>&1 | grep -q "PDU Session Establishment successful" && echo "OK" || echo "FAIL"
    sleep 5
done
```

---

## 8. Extensões Futuras

### 8.1 Múltiplos UEs

Para simular múltiplos UEs, criar namespaces adicionais:

```bash
# UE 2
sudo ip netns add ue2
sudo ip link add veth2 type veth peer name veth3
sudo ip link set veth3 netns ue2
sudo ip addr add 10.45.254.5/30 dev veth2
sudo ip link set veth2 up
sudo ip netns exec ue2 ip addr add 10.45.254.6/30 dev veth3
sudo ip netns exec ue2 ip link set veth3 up
sudo ip netns exec ue2 ip link set lo up
sudo ip netns exec ue2 ip route add default via 10.45.254.5 dev veth3

# Modificar ue_zmq.conf:
# [usim]
# imsi = 001010123456781  # IMSI diferente
# [gw]
# netns = ue2
```

### 8.2 Múltiplos DUs por CU

Docker Swarm facilita scale-out:

```bash
# Aumentar réplicas
docker service scale oran_du_du=3

# Cada DU receberá:
# - IP único na rede f1
# - Conectará à mesma CU (oran_cu_cu resolve para VIP/dnsrr)
# - gNB_ID deve ser único (modificar stack para parametrizar)
```

**Desafio**: Cada DU precisa de porta ZMQ única no host. Soluções:
- Múltiplos hosts no Swarm
- Publicar portas dinâmicas (`published: 0`)

### 8.3 Network Slicing

Open5GS suporta múltiplos slices (SST/SD):

**Configuração SMF** (`/etc/open5gs/smf.yaml`):
```yaml
smf:
  subnet:
    - addr: 10.45.0.0/16
      dnn: internet
    - addr: 10.46.0.0/16
      dnn: iot
      slice:
        - sst: 1
          sd: 0x000001  # Slice para IoT
```

**Subscriber com múltiplos slices**:
```json
{
  "imsi": "001010123456780",
  "slice": [
    {
      "sst": 1,
      "default_indicator": true,
      "session": [{"name": "internet", "type": 3}]
    },
    {
      "sst": 1,
      "sd": "000001",
      "session": [{"name": "iot", "type": 3}]
    }
  ]
}
```

### 8.4 Integração com Near-RT RIC

Para habilitar E2:

1. **Deploy OSC Near-RT RIC**:
```bash
git clone https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep
cd ric-dep/bin
./install -f ../RECIPE_EXAMPLE/PLATFORM/example_recipe.yaml
```

2. **Conectar rede RIC ao Swarm**:
```bash
docker network create --driver overlay \
    --subnet 10.0.2.0/24 \
    --attachable \
    docker_e2

# Atualizar du-ran-stack.yml e cu-ran-stack.yml:
networks:
  e2:
    external: true
    name: docker_e2
```

3. **Habilitar E2**:
```yaml
# du.template.yml
e2:
  enable_du_e2: true
  addr: 10.0.2.10  # IP do RIC
  e2sm_kpm_enabled: true

# cu.template.yml
e2:
  enable_cu_e2: true
  addr: 10.0.2.10
```

---

## 9. Conclusão

Este documento apresentou a implementação completa de uma arquitetura 5G standalone utilizando srsRAN em modo split (CU-DU) orquestrada via Docker Swarm. Através de um processo iterativo de troubleshooting, foram identificados e solucionados diversos desafios técnicos relacionados a:

- **Networking**: Resolução DNS, VIPs do Swarm, isolamento de namespaces
- **Protocolos**: E2AP timeouts, F1-C SCTP binding, ZMQ role inversion
- **Containerização**: Log levels, dynamic IP binding, port publishing modes
- **Orquestração**: Endpoint modes, service discovery, overlay networks

### Principais Contribuições

1. **Documentação detalhada** de uma arquitetura 5G split funcional com Docker Swarm
2. **Identificação e solução** de 8 problemas críticos não documentados
3. **Scripts operacionais** para deployment, monitoring e troubleshooting
4. **Guia de troubleshooting** sistemático para diagnóstico rápido
5. **Base para extensões** (múltiplos UEs/DUs, slicing, RIC integration)

### Lições Aprendidas

- **E2AP deve ser desabilitado** quando não há RIC disponível (evita timeouts de 6 minutos)
- **Docker Swarm VIP** pode causar problemas de routing; `dnsrr` é preferível para serviços únicos
- **ZMQ port publishing** requer `mode: host` para funcionar com IPv4 em Swarm
- **Namespace isolation** requer veth pairs + NAT cuidadosamente configurados
- **Log levels** devem ser ajustados para troubleshooting (F1-C não loga em `info`)

### Trabalhos Futuros

- **RF real** com USRP/LimeSDR substituindo ZMQ
- **Multi-site deployment** com Swarm distribuído em múltiplos hosts
- **RAN Intelligent Controller (RIC)** para otimização dinâmica
- **Performance benchmarking** com ferramentas como iperf3 e latency tests
- **CI/CD pipeline** para deployment automatizado e regression testing

---

## 10. Referências

1. **srsRAN Project Documentation**: https://docs.srsran.com/projects/project/
2. **Open5GS Documentation**: https://open5gs.org/open5gs/docs/
3. **Docker Swarm Documentation**: https://docs.docker.com/engine/swarm/
4. **3GPP TS 38.401**: NG-RAN Architecture description
5. **3GPP TS 38.470**: F1 general aspects and principles
6. **O-RAN WG3**: Near-RT RIC Architecture
7. **ZeroMQ Guide**: https://zguide.zeromq.org/

---

## Apêndices

### Apêndice A: Arquivos de Configuração Completos

**(Incluir os arquivos .yml completos aqui)**

### Apêndice B: Logs de Referência

**(Incluir logs de attach bem-sucedido para cada componente)**

### Apêndice C: Glossário

- **5GC**: 5G Core Network
- **AMF**: Access and Mobility Management Function
- **CU**: Central Unit (split into CU-CP and CU-UP)
- **DU**: Distributed Unit
- **E2AP**: E2 Application Protocol (RAN-RIC interface)
- **F1-C**: F1 Control Plane (DU-CU interface)
- **F1-U**: F1 User Plane (DU-CU interface)
- **gNB**: Next-generation NodeB (5G base station)
- **IMSI**: International Mobile Subscriber Identity
- **N2**: NG-C interface (RAN-AMF)
- **N3**: NG-U interface (RAN-UPF)
- **PLMN**: Public Land Mobile Network
- **PRACH**: Physical Random Access Channel
- **RIC**: RAN Intelligent Controller
- **SMF**: Session Management Function
- **TAC**: Tracking Area Code
- **UE**: User Equipment
- **UPF**: User Plane Function
- **VIP**: Virtual IP (Swarm load balancer)
- **ZMQ**: ZeroMQ (inter-process communication)

---

**Autor**: [Seu Nome]  
**Instituição**: [Sua Universidade]  
**Data**: Novembro 2025  
**Versão**: 1.0

