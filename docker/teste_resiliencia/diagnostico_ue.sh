#!/bin/bash

#
# Script de Diagnóstico UE/ZMQ
# Verifica configurações necessárias para conexão do UE
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Diagnóstico UE/ZMQ Connection         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

check() {
    local desc=$1
    local cmd=$2
    printf "%-50s" "$desc"
    if eval $cmd > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

echo -e "${BLUE}[1] Verificando Infraestrutura${NC}\n"

check "Docker Swarm ativo" "docker info | grep -q 'Swarm: active'"
check "Container 5GC rodando" "docker ps | grep -q 'open5gs_5gc'"
check "Serviço CU ativo" "docker service ls | grep -q 'oran_cu_cu.*1/1'"
check "Serviço DU ativo" "docker service ls | grep -q 'oran_du_du.*1/1'"

echo -e "\n${BLUE}[2] Verificando Porta ZMQ${NC}\n"

if ss -tuln | grep -q "0.0.0.0:2000"; then
    echo -e "${GREEN}✓${NC} DU está escutando em 0.0.0.0:2000 (IPv4)"
    ss -tuln | grep 2000
else
    echo -e "${RED}✗${NC} DU NÃO está escutando em 0.0.0.0:2000"
    echo -e "${YELLOW}  Verificando se está em IPv6 apenas:${NC}"
    ss -tuln | grep 2000 || echo "  Nenhuma porta 2000 encontrada!"
    echo -e "${YELLOW}  Solução: Adicionar 'mode: host' na publicação da porta no du-ran-stack.yml${NC}"
fi

echo -e "\n${BLUE}[3] Verificando Subscriber no Open5GS${NC}\n"

SUBSCRIBER_CHECK=$(docker exec open5gs_5gc mongo mongodb://localhost:27017/open5gs --quiet --eval 'db.subscribers.findOne({imsi: "001010123456780"})' 2>/dev/null)

if echo "$SUBSCRIBER_CHECK" | grep -q "001010123456780"; then
    echo -e "${GREEN}✓${NC} Subscriber 001010123456780 está cadastrado"
else
    echo -e "${RED}✗${NC} Subscriber NÃO está cadastrado"
    echo -e "${YELLOW}  Solução: Cadastrar via WebUI (http://localhost:9999) ou script${NC}"
fi

echo -e "\n${BLUE}[4] Verificando Namespace UE${NC}\n"

if ip netns list | grep -q "ue1"; then
    echo -e "${GREEN}✓${NC} Namespace ue1 existe"
    
    if ip netns exec ue1 ip link show veth1 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Interface veth1 existe no namespace"
        
        if ip netns exec ue1 ip route | grep -q "default"; then
            echo -e "${GREEN}✓${NC} Rota default configurada"
        else
            echo -e "${RED}✗${NC} Rota default NÃO configurada"
        fi
        
        if ip netns exec ue1 ping -c 1 -W 1 10.45.254.1 > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Namespace pode alcançar o host (10.45.254.1)"
        else
            echo -e "${RED}✗${NC} Namespace NÃO pode alcançar o host"
        fi
    else
        echo -e "${RED}✗${NC} Interface veth1 NÃO existe no namespace"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Namespace ue1 não existe (será criado pelo script)"
fi

echo -e "\n${BLUE}[5] Verificando srsUE${NC}\n"

SRSUE_PATH="/home/guilhermemaciel/Documentos/srsRAN/srsRAN_4G/build/srsue/src/srsue"

if [ -f "$SRSUE_PATH" ]; then
    echo -e "${GREEN}✓${NC} srsUE encontrado: $SRSUE_PATH"
else
    echo -e "${RED}✗${NC} srsUE NÃO encontrado em: $SRSUE_PATH"
    echo -e "${YELLOW}  Solução: Compilar srsRAN 4G${NC}"
fi

if pgrep -f "srsue.*ue_zmq" > /dev/null; then
    echo -e "${YELLOW}⚠${NC}  Processo srsUE já está rodando (PID: $(pgrep -f 'srsue.*ue_zmq'))"
else
    echo -e "${GREEN}✓${NC} Nenhum processo srsUE em execução"
fi

echo -e "\n${BLUE}[6] Verificando Logs Recentes${NC}\n"

echo -e "${YELLOW}DU (últimas 5 linhas):${NC}"
docker service logs oran_du_du --tail 5 2>&1 | tail -5

echo -e "\n${YELLOW}CU (últimas 5 linhas):${NC}"
docker service logs oran_cu_cu --tail 5 2>&1 | tail -5

echo -e "\n${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}Diagnóstico Completo${NC}\n"


