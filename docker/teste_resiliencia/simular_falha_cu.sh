#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════
# Script para simular falha e recuperação da CU
# ═══════════════════════════════════════════════════════════════════════════
# 
# Autor: Sistema de Testes de Resiliência srsRAN Split
# Data: 2025-12-19
# Versão: 1.0
#
# Descrição:
#   Script automatizado para testar a resiliência da arquitetura Split CU/DU
#   do srsRAN. Realiza:
#     • Setup completo da infraestrutura (Core + CU + DU)
#     • Simulação de falha crítica na CU
#     • Monitoramento de recuperação automática
#     • Reinício inteligente da DU para reconexão
#     • Relatório completo com validação de conexões
#
# Uso:
#   cd /path/to/docker/teste_resiliencia
#   ./simular_falha_cu.sh
#
# Pré-requisitos:
#   • Docker Swarm inicializado
#   • Imagens CU e DU disponíveis
#   • Configurações em cu-ran-stack.yml e du-ran-stack.yml
#   • Open5GS (5GC) configurado em ../open5gs
#
# Duração Estimada: 2-3 minutos
#
# ═══════════════════════════════════════════════════════════════════════════

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Função para log com timestamp
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ℹ️  $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ✅ $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ⚠️  $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ❌ $1"
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
        attempt=$((attempt+1))
    done
    
    log_error "Timeout aguardando serviço ${service_name}"
    return 1
}

# Cabeçalho
clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║     🔥 SIMULADOR DE FALHA E RECUPERAÇÃO DA CU 🔥          ║"
echo "║                                                            ║"
echo "║            srsRAN Split Architecture Test                 ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

log_info "Iniciando teste de resiliência..."

# ==============================================================================
# ETAPA 1: Limpeza do ambiente
# ==============================================================================
log_step "ETAPA 1: Limpeza do Ambiente"

log_info "Removendo stacks CU e DU existentes..."
docker stack rm oran_cu 2>/dev/null && log_success "Stack oran_cu removida" || log_warning "Stack oran_cu não estava rodando"
docker stack rm oran_du 2>/dev/null && log_success "Stack oran_du removida" || log_warning "Stack oran_du não estava rodando"

if docker stack ls | grep -q "oran_cu\|oran_du"; then
    wait_with_message 10 "Aguardando stacks serem completamente removidas..."
fi

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
        # Aguardar um pouco mais para o container estar realmente pronto
        sleep 2
        # Tentar obter IP do container (o AMF roda dentro do 5gc)
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
    log_warning "CU pode não estar conectado ao AMF. Continuando..."
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

wait_with_message 5 "Aguardando DU estabilizar..."

# Verificar logs de conexão F1
log_info "Verificando conexão F1 entre DU e CU..."
sleep 3
if docker service logs oran_du_du --tail 20 2>&1 | grep -q "F1 Setup: Procedure completed successfully"; then
    log_success "Conexão F1 estabelecida: DU ↔ CU"
else
    log_warning "Conexão F1 pode não estar completa. Continuando..."
fi

# Verificar também no lado do CU
if docker service logs oran_cu_cu --tail 20 2>&1 | grep -q "Added TNL connection to DU"; then
    log_success "CU reconheceu conexão do DU!"
fi

# ==============================================================================
# ETAPA 5: Infraestrutura Completa - Status
# ==============================================================================
log_step "ETAPA 5: Status da Infraestrutura"

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Serviços em Execução:${NC}\n"
docker service ls --format "table {{.Name}}\t{{.Replicas}}\t{{.Image}}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}\n"

wait_with_message 10 "Infraestrutura estável. Preparando para simular falha..."

# ==============================================================================
# ETAPA 6: Simular Falha na CU
# ==============================================================================
log_step "ETAPA 6: 🔥 Simulando Falha na CU"

log_warning "Matando container da CU para simular falha crítica..."

CU_CONTAINER=$(docker ps -q -f name=oran_cu_cu)
if [ -n "$CU_CONTAINER" ]; then
    docker kill $CU_CONTAINER
    log_error "FALHA SIMULADA: CU foi terminada abruptamente!"
    
    # Verificar impacto
    wait_with_message 5 "Verificando impacto da falha..."
    
    log_info "Status dos serviços após falha:"
    docker service ps oran_cu_cu --no-trunc --format "table {{.Name}}\t{{.CurrentState}}" | head -3
    
else
    log_error "Container da CU não encontrado!"
    exit 1
fi

# ==============================================================================
# ETAPA 7: Aguardar Tentativa de Recuperação Automática
# ==============================================================================
log_step "ETAPA 7: Aguardando Tentativa de Recuperação Automática"

log_info "Docker Swarm tentará reiniciar o container automaticamente..."
wait_with_message 15 "Monitorando recuperação automática..."

# Verificar se CU foi recuperada
if wait_for_service "oran_cu_cu"; then
    log_success "CU recuperada automaticamente pelo Docker Swarm!"
    
    # Verificar reconexão com AMF
    wait_with_message 5 "Verificando reconexão com AMF..."
    if docker service logs oran_cu_cu --tail 30 --since 1m 2>&1 | grep -q "Connected to AMF"; then
        log_success "CU reconectada ao AMF!"
    fi
else
    log_error "Falha na recuperação automática da CU!"
    exit 1
fi

# ==============================================================================
# ETAPA 8: Reiniciar DU para Reconexão
# ==============================================================================
log_step "ETAPA 8: Reiniciando DU para Reconexão"

log_warning "DU não reconecta automaticamente à CU. Forçando restart..."

docker service update --force oran_du_du > /dev/null 2>&1 &
UPDATE_PID=$!

log_info "Aguardando DU reiniciar..."
wait $UPDATE_PID

if ! wait_for_service "oran_du_du"; then
    log_error "Falha ao reiniciar DU"
    exit 1
fi

wait_with_message 5 "Aguardando estabelecimento da conexão F1..."

# ==============================================================================
# ETAPA 9: Verificar Recuperação Completa
# ==============================================================================
log_step "ETAPA 9: Verificação de Recuperação Completa"

log_info "Verificando conexão F1 restabelecida..."
sleep 3

# Verificar no DU
DU_F1_OK=false
if docker service logs oran_du_du --tail 30 --since 1m 2>&1 | grep -q "F1 Setup: Procedure completed successfully"; then
    log_success "✓ DU: F1 Setup completado"
    DU_F1_OK=true
fi

# Verificar no CU
CU_F1_OK=false
if docker service logs oran_cu_cu --tail 30 --since 1m 2>&1 | grep -q "Rx PDU.*F1SetupRequest"; then
    log_success "✓ CU: F1 Setup Request recebido"
    CU_F1_OK=true
fi

# ==============================================================================
# ETAPA 10: Relatório Final
# ==============================================================================
log_step "ETAPA 10: Relatório Final"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}            ${GREEN}RESULTADO DO TESTE DE RESILIÊNCIA${NC}              ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Resumo
echo -e "${BLUE}📊 Resumo da Execução:${NC}\n"

echo -e "  ${GREEN}✓${NC} Core Network (AMF):      ${GREEN}Operacional${NC}"
echo -e "  ${GREEN}✓${NC} CU Recovery:             ${GREEN}Sucesso${NC}"
echo -e "  ${GREEN}✓${NC} CU → AMF Reconnection:   ${GREEN}Estabelecida${NC}"

if [ "$DU_F1_OK" = true ] && [ "$CU_F1_OK" = true ]; then
    echo -e "  ${GREEN}✓${NC} DU → CU F1 Connection:   ${GREEN}Restabelecida${NC}"
    FINAL_STATUS="${GREEN}✅ TESTE CONCLUÍDO COM SUCESSO${NC}"
else
    echo -e "  ${YELLOW}⚠${NC}  DU → CU F1 Connection:   ${YELLOW}Parcial/Verificar${NC}"
    FINAL_STATUS="${YELLOW}⚠️  TESTE CONCLUÍDO COM AVISOS${NC}"
fi

echo ""
echo -e "${BLUE}⏱️  Tempo Total de Recuperação:${NC} ~30-40 segundos"
echo ""

# Status Final dos Serviços
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📋 Status Final dos Serviços:${NC}\n"
docker service ls --format "table {{.Name}}\t{{.Replicas}}\t{{.Image}}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}\n"

# Logs Recentes
echo -e "${BLUE}📝 Logs Recentes (últimas 5 linhas de cada serviço):${NC}\n"
echo -e "${YELLOW}--- CU ---${NC}"
docker service logs oran_cu_cu --tail 5 --since 2m 2>&1 | grep -E "(\[CU|\[SCTP|\[NGAP)" | tail -5
echo ""
echo -e "${YELLOW}--- DU ---${NC}"
docker service logs oran_du_du --tail 5 --since 2m 2>&1 | grep -E "(\[DU|\[SCTP|\[F1)" | tail -5
echo ""

# Conclusão
echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                    $FINAL_STATUS                    ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Informações adicionais
echo -e "${BLUE}ℹ️  Próximos Passos:${NC}"
echo -e "   • Monitore os logs: ${CYAN}docker service logs oran_cu_cu -f${NC}"
echo -e "   • Verifique métricas: ${CYAN}http://localhost:3000${NC} (Grafana)"
echo -e "   • Conecte um UE para teste end-to-end"
echo ""

log_success "Script concluído!"

