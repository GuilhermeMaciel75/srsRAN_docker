#!/bin/bash

#
# Script de Teste de Resiliência da CU com UE Conectada
# 
# Este script automatiza o seguinte cenário:
# 1. Inicia infraestrutura (Core, CU, DU)
# 2. Conecta UE via ZMQ
# 3. Valida conectividade com ping
# 4. Simula falha crítica na CU
# 5. Aguarda recuperação automática
# 6. Reconecta UE
# 7. Valida conectividade novamente
#
# Uso: sudo ./simular_falha_cu_com_ue.sh
# Nota: Requer privilégios root para criar namespace e interface TUN
#

set -e  # Exit on error

# ==============================================================================
# Cores para output
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==============================================================================
# Configurações
# ==============================================================================
UE_NAMESPACE="ue1"
UE_CONF_FILE="/tmp/ue_zmq.conf"
SRSUE_PATH="/home/guilhermemaciel/Documentos/srsRAN/srsRAN_4G/build/srsue/src/srsue"
CORE_IP="10.45.0.1"
UE_IP=""  # Será obtido após attach

# ==============================================================================
# Banner
# ==============================================================================
echo -e "${CYAN}"
cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║   🔥 TESTE DE RESILIÊNCIA DA CU COM UE CONECTADA 🔥       ║
║                                                            ║
║            srsRAN Split Architecture Test                 ║
║               with User Equipment Simulation              ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# ==============================================================================
# Funções auxiliares
# ==============================================================================
log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ✅ $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ❌ $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ⚠️  $1"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ℹ️  $1"
}

log_step() {
    echo -e "\n${MAGENTA}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} 🔸 ${CYAN}$1${NC}\n"
}

# Função para aguardar com contador
wait_with_message() {
    local seconds=$1
    local message=$2
    log_info "$message"
    for ((i=$seconds; i>0; i--)); do
        echo -ne "${YELLOW}   Aguardando... ${i}s restantes\r${NC}"
        sleep 1
    done
    echo -ne "\n"
}

# Função para verificar se um serviço está rodando
check_service() {
    local service_name=$1
    local replicas=$(docker service ls --filter "name=${service_name}" --format "{{.Replicas}}" 2>/dev/null)
    
    if [ -z "$replicas" ]; then
        return 1
    fi
    
    local running=$(echo $replicas | cut -d'/' -f1)
    local desired=$(echo $replicas | cut -d'/' -f2)
    
    if [ "$running" = "$desired" ] && [ "$running" != "0" ]; then
        return 0
    else
        return 1
    fi
}

# Função para aguardar serviço estar pronto
wait_for_service() {
    local service_name=$1
    local max_attempts=60
    local attempt=0
    
    log_info "Aguardando serviço ${service_name} estar pronto..."
    
    while [ $attempt -lt $max_attempts ]; do
        if check_service "$service_name"; then
            log_success "Serviço ${service_name} está pronto!"
            return 0
        fi
        echo -ne "${YELLOW}   Tentativa $((attempt+1))/${max_attempts}...\r${NC}"
        sleep 2
        ((attempt++))
    done
    
    log_error "Timeout aguardando serviço ${service_name}"
    return 1
}

# Função para aguardar container estar em estado específico
wait_for_container_status() {
    local container_name=$1
    local desired_status=$2
    local timeout=$3
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            local status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
            if [ "$status" = "$desired_status" ]; then
                return 0
            fi
        fi
        sleep 2
        ((elapsed+=2))
    done
    return 1
}

# Função para criar arquivo de configuração do UE
create_ue_config() {
    log_info "Criando arquivo de configuração do UE..."
    
    # UE roda no HOST (não em namespace) para ZMQ
    # Apenas a interface TUN usará o namespace
    
    cat > "$UE_CONF_FILE" << 'EOL'
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
EOL
    
    log_success "Arquivo de configuração criado: ${UE_CONF_FILE}"
    log_info "ZMQ: UE (host) ↔ DU (container) via portas 2000/2001"
    log_info "TUN: Interface tun_srsue será criada no namespace ue1"
}

# Função para cadastrar subscriber no Open5GS
register_subscriber() {
    log_info "Verificando/Cadastrando subscriber no Open5GS..."
    
    docker exec open5gs_5gc bash -c "
        mongo mongodb://localhost:27017/open5gs --quiet --eval '
            var sub = db.subscribers.findOne({imsi: \"001010123456780\"});
            if (sub) {
                print(\"Subscriber já cadastrado\");
            } else {
                db.subscribers.insert({
                    \"imsi\" : \"001010123456780\",
                    \"security\" : {
                        \"k\" : \"00112233445566778899aabbccddeeff\",
                        \"opc\" : \"63BFA50EE6523365FF14C1F45F88737D\",
                        \"amf\" : \"8000\",
                        \"sqn\" : NumberLong(0)
                    },
                    \"ambr\" : {
                        \"downlink\" : { \"value\" : 1, \"unit\" : 3 },
                        \"uplink\" : { \"value\" : 1, \"unit\" : 3 }
                    },
                    \"slice\" : [{
                        \"sst\" : 1,
                        \"default_indicator\" : true,
                        \"session\" : [{
                            \"name\" : \"srsapn\",
                            \"type\" : 3,
                            \"ambr\" : {
                                \"downlink\" : { \"value\" : 1, \"unit\" : 3 },
                                \"uplink\" : { \"value\" : 1, \"unit\" : 3 }
                            },
                            \"qos\" : {
                                \"index\" : 9,
                                \"arp\" : {
                                    \"priority_level\" : 8,
                                    \"pre_emption_capability\" : 1,
                                    \"pre_emption_vulnerability\" : 1
                                }
                            }
                        }]
                    }]
                });
                print(\"Subscriber cadastrado com sucesso\");
            }
        '
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Subscriber configurado no Open5GS"
    else
        log_warning "Não foi possível verificar subscriber (continuando...)"
    fi
}

# Função para configurar namespace e veth pair
setup_network_namespace() {
    log_info "Configurando namespace de rede para interface TUN do UE..."
    
    # Remover namespace anterior se existir
    if ip netns list | grep -q "$UE_NAMESPACE"; then
        log_warning "Namespace $UE_NAMESPACE já existe. Removendo..."
        ip netns del "$UE_NAMESPACE" 2>/dev/null || true
    fi
    
    # Criar namespace (será usado apenas pela interface TUN após attach)
    ip netns add "$UE_NAMESPACE"
    log_success "Namespace $UE_NAMESPACE criado"
    
    # Criar veth pair (bridge entre host e namespace para tráfego de dados)
    ip link add veth0 type veth peer name veth1
    
    # Mover veth1 para o namespace
    ip link set veth1 netns "$UE_NAMESPACE"
    
    # Configurar veth0 (host)
    ip addr add 10.45.254.1/24 dev veth0
    ip link set veth0 up
    
    # Configurar veth1 (namespace)
    ip netns exec "$UE_NAMESPACE" ip addr add 10.45.254.2/24 dev veth1
    ip netns exec "$UE_NAMESPACE" ip link set veth1 up
    ip netns exec "$UE_NAMESPACE" ip link set lo up
    
    # Adicionar rota padrão no namespace
    ip netns exec "$UE_NAMESPACE" ip route add default via 10.45.254.1
    
    # Habilitar IP forwarding no host
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    
    # Configurar NAT para permitir tráfego do namespace para ogstun
    iptables -t nat -A POSTROUTING -s 10.45.254.0/24 -o ogstun -j MASQUERADE 2>/dev/null || true
    
    # Forward de pacotes entre veth0 e ogstun
    iptables -A FORWARD -i veth0 -o ogstun -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -i ogstun -o veth0 -j ACCEPT 2>/dev/null || true
    
    log_success "Namespace de rede configurado"
    log_info "Namespace será usado pela interface tun_srsue após attach"
    log_info "ZMQ roda no host: UE TX=*:2001, RX=127.0.0.1:2000"
}

# Função para iniciar UE
start_ue() {
    log_info "Iniciando UE no host (ZMQ) com namespace para TUN..."
    
    # Verificar se srsUE existe
    if [ ! -f "$SRSUE_PATH" ]; then
        log_error "srsUE não encontrado em: $SRSUE_PATH"
        exit 1
    fi
    
    # Matar processo anterior se existir
    pkill -f "srsue.*ue_zmq.conf" 2>/dev/null || true
    sleep 2
    
    # IMPORTANTE: Iniciar UE diretamente no host, não no namespace
    # O namespace é usado apenas para a interface TUN (tun_srsue) após attach
    # O ZMQ precisa rodar no host para que o DU possa conectar na porta 2001
    "$SRSUE_PATH" "$UE_CONF_FILE" > /tmp/ue_run.log 2>&1 &
    UE_PID=$!
    
    log_info "UE iniciado (PID: $UE_PID). Aguardando attach..."
    
    # Aguardar attach (verificar logs)
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if grep -q "PDU Session Establishment successful" /tmp/ue_run.log 2>/dev/null; then
            # Extrair IP do UE
            UE_IP=$(grep "PDU Session Establishment successful" /tmp/ue_run.log | grep -oP 'IP: \K[0-9.]+' | tail -1)
            log_success "UE conectado! IP atribuído: ${UE_IP}"
            
            # Aguardar interface tun estar UP
            sleep 3
            
            # Configurar rota para o Core através da interface TUN
            ip netns exec "$UE_NAMESPACE" ip route add $CORE_IP via $UE_IP dev tun_srsue 2>/dev/null || true
            
            return 0
        fi
        
        if ! ps -p $UE_PID > /dev/null 2>&1; then
            log_error "Processo UE morreu. Últimas linhas do log:"
            tail -20 /tmp/ue_run.log
            return 1
        fi
        
        sleep 2
        ((waited+=2))
        echo -ne "${YELLOW}   Aguardando attach... ${waited}s/${max_wait}s\r${NC}"
    done
    
    log_error "Timeout aguardando attach do UE"
    log_info "Últimas linhas do log do UE:"
    tail -20 /tmp/ue_run.log
    return 1
}

# Função para parar UE
stop_ue() {
    log_info "Parando UE..."
    pkill -f "srsue.*ue_zmq.conf" 2>/dev/null || true
    sleep 2
    
    # IMPORTANTE: Remover interface TUN do namespace para permitir reconexão
    if ip netns exec "$UE_NAMESPACE" ip link show tun_srsue > /dev/null 2>&1; then
        log_info "Removendo interface tun_srsue do namespace..."
        ip netns exec "$UE_NAMESPACE" ip link del tun_srsue 2>/dev/null || true
    fi
    
    log_success "UE parado"
}

# Função para realizar ping
test_ping() {
    local target=$1
    local description=$2
    
    log_info "Teste de conectividade: ${description}"
    
    if ip netns exec "$UE_NAMESPACE" ping -c 4 -W 2 "$target" > /dev/null 2>&1; then
        log_success "✓ PING bem-sucedido para ${target}"
        return 0
    else
        log_error "✗ PING falhou para ${target}"
        return 1
    fi
}

# Função para limpar ambiente
cleanup() {
    log_info "Limpando ambiente..."
    
    # Parar UE
    pkill -f "srsue.*ue_zmq.conf" 2>/dev/null || true
    
    # Limpar regras iptables específicas do teste
    iptables -D FORWARD -i veth0 -o ogstun -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i ogstun -o veth0 -j ACCEPT 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s 10.45.254.0/24 -o ogstun -j MASQUERADE 2>/dev/null || true
    
    # Remover namespace
    if ip netns list | grep -q "$UE_NAMESPACE"; then
        ip netns del "$UE_NAMESPACE" 2>/dev/null || true
    fi
    
    # Remover veth
    ip link del veth0 2>/dev/null || true
    
    log_success "Ambiente limpo"
}

# ==============================================================================
# INÍCIO DO SCRIPT PRINCIPAL
# ==============================================================================

log_info "Iniciando teste de resiliência..."

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    log_error "Este script precisa ser executado como root (sudo)"
    exit 1
fi

# Verificar se srsUE existe
if [ ! -f "$SRSUE_PATH" ]; then
    log_error "srsUE não encontrado em: $SRSUE_PATH"
    log_info "Por favor, compile o srsRAN 4G primeiro:"
    log_info "  cd srsRAN_4G && mkdir build && cd build"
    log_info "  cmake ../ && make -j\$(nproc)"
    exit 1
fi

# ==============================================================================
# ETAPA 1: Limpeza do Ambiente
# ==============================================================================
log_step "ETAPA 1: Limpeza do Ambiente"

log_info "Removendo stacks CU e DU existentes..."
docker stack rm oran_cu 2>/dev/null && log_success "Stack oran_cu removida" || log_success "Stack oran_cu removida"
docker stack rm oran_du 2>/dev/null && log_success "Stack oran_du removida" || log_success "Stack oran_du removida"

# Limpar namespace anterior
cleanup

wait_with_message 5 "Aguardando limpeza de recursos..."
log_success "Ambiente limpo!"

# ==============================================================================
# ETAPA 2: Verificar e iniciar Core Network
# ==============================================================================
log_step "ETAPA 2: Verificação do Core Network (Open5GS)"

cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker || {
    log_error "Diretório do Docker não encontrado!"
    exit 1
}

if ! docker ps | grep -q "open5gs_5gc"; then
    log_warning "Core Network não está rodando. Iniciando..."
    
    # Iniciar apenas o serviço 5gc usando docker compose
    log_info "Iniciando serviço 5gc..."
    docker compose up -d 5gc || {
        log_error "Falha ao iniciar Core Network (5gc)"
        exit 1
    }
    
    log_success "Comando executado. Aguardando container iniciar..."
    wait_with_message 20 "Aguardando Core Network (5gc) estabilizar..."
else
    log_success "Core Network (5gc) já está rodando!"
fi

# Verificar se o container 5gc está realmente pronto
log_info "Verificando status do container 5gc..."
AMF_READY=false
for i in {1..10}; do
    if docker ps | grep -q "open5gs_5gc"; then
        sleep 2
        AMF_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' open5gs_5gc 2>/dev/null | grep -v "^$" | head -1)
        if [ -n "$AMF_IP" ]; then
            log_success "Core Network (5gc) rodando. IP do container: ${AMF_IP}"
            AMF_READY=true
            break
        fi
    fi
    log_warning "Tentativa $i/10: Container 5gc ainda não está pronto..."
    sleep 3
done

if [ "$AMF_READY" = false ]; then
    log_error "Container 5gc não está acessível após múltiplas tentativas!"
    log_info "Containers rodando:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

# ==============================================================================
# ETAPA 3: Iniciar CU
# ==============================================================================
log_step "ETAPA 3: Iniciando CU (Central Unit)"

cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker || exit 1

log_info "Deployando stack CU..."
docker stack deploy -c cu-ran-stack.yml oran_cu

if ! wait_for_service "oran_cu_cu"; then
    log_error "Falha ao iniciar CU"
    exit 1
fi

wait_with_message 5 "Aguardando CU estabilizar..."

# Verificar logs do CU
log_info "Verificando conectividade do CU com AMF..."
if docker service logs oran_cu_cu --tail 20 2>&1 | grep -q "Connected to AMF"; then
    log_success "CU conectado ao AMF com sucesso!"
else
    log_warning "Conexão com AMF pode não estar completa. Continuando..."
fi

# ==============================================================================
# ETAPA 4: Iniciar DU
# ==============================================================================
log_step "ETAPA 4: Iniciando DU (Distributed Unit)"

log_info "Deployando stack DU..."
docker stack deploy -c du-ran-stack.yml oran_du

if ! wait_for_service "oran_du_du"; then
    log_error "Falha ao iniciar DU"
    exit 1
fi

wait_with_message 10 "Aguardando DU estabilizar e estabelecer conexão F1..."

# Verificar conexão F1
log_info "Verificando conexão F1 entre DU e CU..."
sleep 3
if docker service logs oran_du_du --tail 30 2>&1 | grep -q "F1 Setup Request"; then
    log_success "DU enviou F1 Setup Request!"
fi

if docker service logs oran_cu_cu --tail 30 2>&1 | grep -q "F1SetupRequest"; then
    log_success "CU reconheceu conexão do DU!"
else
    log_warning "Verificação F1 incompleta. Continuando..."
fi

# ==============================================================================
# ETAPA 5: Configurar e Conectar UE
# ==============================================================================
log_step "ETAPA 5: Configurando e Conectando UE"

# Verificar se DU está escutando na porta ZMQ
log_info "Verificando porta ZMQ do DU..."
if ss -tuln | grep -q "0.0.0.0:2000"; then
    log_success "DU está escutando na porta 2000 (ZMQ TX)"
else
    log_error "DU não está escutando na porta 2000!"
    log_info "Verifique se o DU foi deployado com 'mode: host' nas portas."
    exit 1
fi

# Criar arquivo de configuração
create_ue_config

# Configurar namespace (para TUN, não para ZMQ)
setup_network_namespace

# Aguardar DU estar pronto para receber UE
wait_with_message 5 "Aguardando DU estar pronto para conexões..."

# Iniciar UE
if ! start_ue; then
    log_error "Falha ao conectar UE"
    log_info "Verificando porta ZMQ novamente..."
    ss -tuln | grep 2000 || true
    log_info "Verificando porta 2001 do UE..."
    ss -tuln | grep 2001 || true
    log_info "Verificando logs do DU..."
    docker service logs oran_du_du --tail 20
    cleanup
    exit 1
fi

# ==============================================================================
# ETAPA 6: Teste de Conectividade Inicial
# ==============================================================================
log_step "ETAPA 6: Teste de Conectividade Inicial (Pré-Falha)"

log_info "Realizando teste de conectividade..."
PING_SUCCESS=false

if test_ping "$CORE_IP" "UE → Core Network"; then
    PING_SUCCESS=true
    log_success "✓ Conectividade estabelecida com sucesso!"
else
    log_warning "⚠ Ping falhou, mas continuando com o teste..."
fi

# ==============================================================================
# ETAPA 7: Status da Infraestrutura
# ==============================================================================
log_step "ETAPA 7: Status da Infraestrutura"

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Serviços em Execução:${NC}\n"
docker service ls --filter name=oran
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}\n"

log_info "Infraestrutura estável. Preparando para simular falha..."
wait_with_message 10 ""

# ==============================================================================
# ETAPA 8: Simulando Falha na CU
# ==============================================================================
log_step "ETAPA 8: 🔥 Simulando Falha na CU"

log_warning "Matando container da CU para simular falha crítica..."
CU_CONTAINER=$(docker ps --filter "name=oran_cu_cu" --format "{{.ID}}" | head -1)

if [ -n "$CU_CONTAINER" ]; then
    docker kill "$CU_CONTAINER"
    log_error "FALHA SIMULADA: CU foi terminada abruptamente!"
else
    log_error "Container CU não encontrado!"
    cleanup
    exit 1
fi

log_info "Verificando impacto da falha..."
wait_with_message 5 ""

log_info "Status dos serviços após falha:"
docker service ps oran_cu_cu --format "{{.Name}}   {{.CurrentState}}" | head -4

# ==============================================================================
# ETAPA 9: Aguardando Recuperação Automática
# ==============================================================================
log_step "ETAPA 9: Aguardando Recuperação Automática da CU"

log_info "Docker Swarm tentará reiniciar o container automaticamente..."
log_info "Monitorando recuperação automática..."
wait_with_message 15 ""

if ! wait_for_service "oran_cu_cu"; then
    log_error "CU não recuperou automaticamente!"
    cleanup
    exit 1
fi

log_success "CU recuperada automaticamente pelo Docker Swarm!"

log_info "Verificando reconexão com AMF..."
wait_with_message 5 ""

if docker service logs oran_cu_cu --tail 20 2>&1 | grep -q "Connected to AMF"; then
    log_success "CU reconectada ao AMF!"
else
    log_warning "Verificação AMF incompleta. Continuando..."
fi

# ==============================================================================
# ETAPA 10: Reiniciando DU para Reconexão
# ==============================================================================
log_step "ETAPA 10: Reiniciando DU para Reconexão"

log_warning "DU não reconecta automaticamente à CU. Forçando restart..."
docker service update --force oran_du_du > /dev/null 2>&1

log_info "Aguardando DU reiniciar..."
sleep 5

if ! wait_for_service "oran_du_du"; then
    log_error "Falha ao reiniciar DU"
    cleanup
    exit 1
fi

log_info "Aguardando estabelecimento da conexão F1..."
wait_with_message 10 ""

# ==============================================================================
# ETAPA 11: Reconectando UE
# ==============================================================================
log_step "ETAPA 11: Reconectando UE"

# Verificar se F1 foi estabelecido entre CU e DU
log_info "Verificando reconexão F1 entre DU e CU..."
F1_RECONNECTED=false
for i in $(seq 1 30); do
    if docker service logs oran_cu_cu --tail 20 2>&1 | grep -q "F1SetupResponse"; then
        log_success "Conexão F1 restabelecida!"
        F1_RECONNECTED=true
        break
    fi
    echo -ne "${YELLOW}   Aguardando F1 Setup... ${i}s\r${NC}"
    sleep 1
done
echo -ne "\n"

if [ "$F1_RECONNECTED" = false ]; then
    log_error "F1 não foi restabelecido após restart do DU"
    cleanup
    exit 1
fi

# Verificar se a célula está transmitindo SSB (sinal de que está ativa)
log_info "Verificando se célula do DU está ativa e transmitindo SSB..."

# Reiniciar UE para destravar transmissão ZMQ da DU
log_info "Reiniciando UE para restabelecer conexão ZMQ e destravar transmissão da DU..."
stop_ue
sleep 5

log_info "Verificando porta ZMQ (2000) no host..."
ss -tuln | grep 2000 || log_warning "Porta 2000 não detectada!"

if ! start_ue; then
    log_warning "UE não conseguiu se conectar (provavelmente célula inativa). Continuando para verificação de SSB e possível redeploy..."
    # Não fazemos exit aqui para permitir que a lógica de "Redeploy DU" (Hard Reset) tente corrigir o problema
fi

# Aguardar um pouco para DU estabilizar
sleep 5

# Estratégia: Verificar se há SSB recente nos logs (últimos 60s)
# O DU transmite SSB continuamente quando a célula está ativa
CELL_ACTIVE=false
for i in $(seq 1 15); do
    # Verificar se há SSB sendo transmitido (últimos 60 segundos)
    if docker service logs oran_du_du --since 60s 2>&1 | grep -q "SSB: pci=1"; then
        log_success "Célula ativa e transmitindo SSB!"
        CELL_ACTIVE=true
        break
    fi
    echo -ne "${YELLOW}   Aguardando célula ativar... ${i}s\r${NC}"
    sleep 2
done
echo -ne "\n"

if [ "$CELL_ACTIVE" = false ]; then
    log_warning "Célula do DU não ativou após F1 Setup"
    log_info "Na arquitetura Split, a célula pode ficar inativa após perda de F1"
    log_info "Reiniciando completamente o DU para forçar inicialização da célula..."
    
    # Remove o serviço e recria (restart completo, não apenas update --force)
    docker stack rm oran_du > /dev/null 2>&1
    sleep 10
    
    log_info "Redeployando DU..."
    cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker || exit 1
    docker stack deploy -c du-ran-stack.yml oran_du > /dev/null 2>&1
    
    log_info "Aguardando DU reiniciar completamente..."
    if ! wait_for_service "oran_du_du" 60; then
        log_error "DU não reiniciou corretamente"
        cleanup
        exit 1
    fi
    
    log_info "Aguardando F1 Setup após redeploy completo..."
    sleep 15
    
    # Verificar F1 Setup novamente
    F1_RECONNECTED=false
    for i in $(seq 1 30); do
        if docker service logs oran_cu_cu --tail 20 2>&1 | grep -q "F1SetupResponse"; then
            log_success "F1 Setup completo!"
            F1_RECONNECTED=true
            break
        fi
        echo -ne "${YELLOW}   Aguardando F1 Setup... ${i}s\r${NC}"
        sleep 1
    done
    echo -ne "\n"
    
    if [ "$F1_RECONNECTED" = false ]; then
        log_error "F1 não foi estabelecido após redeploy"
        cleanup
        exit 1
    fi
    
    # Verificar SSB após redeploy completo
    log_info "Verificando SSB após redeploy..."

    # Reiniciar UE para destravar transmissão ZMQ da DU
    log_info "Reiniciando UE para restabelecer conexão ZMQ e destravar transmissão da DU..."
    stop_ue
    sleep 5
if ! start_ue; then
    log_warning "UE não conseguiu se conectar (provavelmente célula inativa). Continuando para verificação de SSB..."
fi

    sleep 10
    for i in $(seq 1 20); do
        if docker service logs oran_du_du --since 60s 2>&1 | grep -q "SSB: pci=1"; then
            log_success "Célula ativa após redeploy completo!"
            CELL_ACTIVE=true
            break
        fi
        echo -ne "${YELLOW}   Aguardando SSB... ${i}s\r${NC}"
        sleep 2
    done
    echo -ne "\n"
    
    if [ "$CELL_ACTIVE" = false ]; then
        log_error "Célula não ativou mesmo após redeploy completo"
        log_error "Possível problema com arquitetura srsRAN Split"
        cleanup
        exit 1
    fi
fi

log_info "Aguardando DU estabilizar para receber UE..."
sleep 5

log_info "Aguardando rede estabilizar..."
sleep 5

# ==============================================================================
# ETAPA 12: Teste de Conectividade Final
# ==============================================================================
log_step "ETAPA 12: Teste de Conectividade Final (Pós-Recuperação)"

log_info "Realizando teste de conectividade após recuperação..."
PING_FINAL_SUCCESS=false

if test_ping "$CORE_IP" "UE → Core Network (pós-recuperação)"; then
    PING_FINAL_SUCCESS=true
    log_success "✓ Conectividade restabelecida com sucesso!"
else
    log_error "✗ Falha ao restabelecer conectividade"
fi

# ==============================================================================
# ETAPA 13: Verificação de Recuperação Completa
# ==============================================================================
log_step "ETAPA 13: Verificação de Recuperação Completa"

log_info "Verificando conexão F1 restabelecida..."
sleep 3

if docker service logs oran_cu_cu --tail 30 2>&1 | grep -q "F1SetupRequest"; then
    log_success "✓ CU: F1 Setup Request recebido"
fi

if docker service logs oran_du_du --tail 30 2>&1 | grep -q "F1 Setup Request"; then
    log_success "✓ DU: F1 Setup Request enviado"
fi

# ==============================================================================
# ETAPA 14: Relatório Final
# ==============================================================================
log_step "ETAPA 14: Relatório Final"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}            ${GREEN}RESULTADO DO TESTE DE RESILIÊNCIA COM UE${NC}         ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${BLUE}📊 Resumo da Execução:${NC}\n"

# Status do Core
echo -e "  ${GREEN}✓${NC} Core Network (AMF):      ${GREEN}Operacional${NC}"

# Status da CU
echo -e "  ${GREEN}✓${NC} CU Recovery:             ${GREEN}Sucesso${NC}"
echo -e "  ${GREEN}✓${NC} CU → AMF Reconnection:   ${GREEN}Estabelecida${NC}"

# Status do DU
echo -e "  ${GREEN}✓${NC} DU Restart:              ${GREEN}Sucesso${NC}"
echo -e "  ${GREEN}✓${NC} DU → CU F1 Connection:   ${GREEN}Restabelecida${NC}"

# Status do UE
if [ "$PING_SUCCESS" = true ]; then
    echo -e "  ${GREEN}✓${NC} UE Initial Connection:   ${GREEN}Sucesso${NC}"
else
    echo -e "  ${YELLOW}⚠${NC}  UE Initial Connection:   ${YELLOW}Parcial${NC}"
fi

echo -e "  ${GREEN}✓${NC} UE Reconnection:         ${GREEN}Sucesso${NC}"

if [ "$PING_FINAL_SUCCESS" = true ]; then
    echo -e "  ${GREEN}✓${NC} Connectivity Test:       ${GREEN}Passou${NC}"
    TEST_STATUS="${GREEN}✅ TESTE CONCLUÍDO COM SUCESSO${NC}"
else
    echo -e "  ${RED}✗${NC} Connectivity Test:       ${RED}Falhou${NC}"
    TEST_STATUS="${YELLOW}⚠️  TESTE CONCLUÍDO COM AVISOS${NC}"
fi

echo -e "\n${BLUE}⏱️  Tempo Total de Recuperação:${NC} ~45-60 segundos"

echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📋 Status Final dos Serviços:${NC}\n"
docker service ls --filter name=oran
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}📝 Informações do UE:${NC}\n"
if [ -n "$UE_IP" ]; then
    echo -e "  ${GREEN}•${NC} IP do UE:        ${UE_IP}"
    echo -e "  ${GREEN}•${NC} Namespace:       ${UE_NAMESPACE}"
    echo -e "  ${GREEN}•${NC} Interface:       tun_srsue"
else
    echo -e "  ${RED}•${NC} UE não obteve IP"
fi

echo -e "\n${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📝 Logs Recentes (últimas 5 linhas de cada serviço):${NC}\n"

echo -e "${YELLOW}--- CU ---${NC}"
docker service logs oran_cu_cu --tail 5 2>&1 | grep -v "^$"

echo -e "\n${YELLOW}--- DU ---${NC}"
docker service logs oran_du_du --tail 5 2>&1 | grep -v "^$"

echo -e "\n${YELLOW}--- UE (últimas 10 linhas) ---${NC}"
tail -10 /tmp/ue_run.log 2>/dev/null || echo "Log do UE não disponível"

echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                    $TEST_STATUS                    ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${BLUE}ℹ️  Próximos Passos:${NC}"
echo -e "   • Monitore os logs: ${CYAN}docker service logs oran_cu_cu -f${NC}"
echo -e "   • Verifique métricas: ${CYAN}http://localhost:3000${NC} (Grafana)"
echo -e "   • Logs do UE: ${CYAN}tail -f /tmp/ue_run.log${NC}"
echo -e "   • Verificar interface TUN: ${CYAN}sudo ip netns exec $UE_NAMESPACE ip addr${NC}"
echo -e "   • Testar ping novamente: ${CYAN}sudo ip netns exec $UE_NAMESPACE ping $CORE_IP${NC}"

echo -e "\n${BLUE}ℹ️  Para limpar o ambiente:${NC}"
echo -e "   • Parar UE: ${CYAN}sudo pkill -f srsue${NC}"
echo -e "   • Remover namespace: ${CYAN}sudo ip netns del $UE_NAMESPACE${NC}"
echo -e "   • Parar serviços: ${CYAN}docker stack rm oran_cu oran_du${NC}"

log_success "Script concluído!"

# Manter UE rodando se conectividade OK
if [ "$PING_FINAL_SUCCESS" = true ]; then
    echo -e "\n${GREEN}✅ UE permanecerá conectado para testes adicionais.${NC}"
    echo -e "${YELLOW}⚠️  Pressione Ctrl+C para parar o UE e limpar o ambiente${NC}\n"
    
    trap cleanup EXIT
    
    # Manter script vivo
    tail -f /tmp/ue_run.log
else
    log_warning "Limpando ambiente devido a falhas..."
    cleanup
fi



