#!/bin/bash
# Script de teste rápido para validar conectividade iperf3

set -e

CORE_IP="10.53.1.2"
CORE_CONTAINER="open5gs_5gc"
DURATION=10

echo "=== Teste Rápido de Conectividade iperf3 ==="
echo ""

# 1. Verificar container
echo "[1] Verificando container $CORE_CONTAINER..."
if ! docker ps | grep -q "$CORE_CONTAINER"; then
    echo "✗ Container não está rodando!"
    exit 1
fi
echo "✓ Container rodando"
echo ""

# 2. Verificar iperf3 no container
echo "[2] Verificando iperf3 no container..."
if ! docker exec "$CORE_CONTAINER" which iperf3 &> /dev/null; then
    echo "Instalando iperf3..."
    docker exec "$CORE_CONTAINER" apt-get update -qq
    docker exec "$CORE_CONTAINER" apt-get install -y iperf3
fi
echo "✓ iperf3 instalado"
echo ""

# 3. Verificar UE
echo "[3] Verificando UE..."
UE_IP=$(sudo ip netns exec ue1 ip addr show tun_srsue 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if [ -z "$UE_IP" ]; then
    echo "✗ UE não está conectado (sem IP em tun_srsue)"
    echo "Inicie o UE primeiro!"
    exit 1
fi
echo "✓ UE conectado com IP: $UE_IP"
echo ""

# 4. Testar conectividade básica
echo "[4] Testando ping do UE para 5GC..."
if sudo ip netns exec ue1 ping -c 3 $CORE_IP > /dev/null 2>&1; then
    echo "✓ Ping funcionando"
else
    echo "✗ Ping falhou!"
    echo "Tentando ping com saída:"
    sudo ip netns exec ue1 ping -c 3 $CORE_IP
fi
echo ""

# 5. Iniciar servidor iperf3
echo "[5] Iniciando servidor iperf3 no container..."
docker exec "$CORE_CONTAINER" pkill -9 iperf3 || true
sleep 2

echo "Comando: docker exec $CORE_CONTAINER bash -c 'nohup iperf3 -s > /tmp/iperf3_server.log 2>&1 &'"
docker exec "$CORE_CONTAINER" bash -c "nohup iperf3 -s > /tmp/iperf3_server.log 2>&1 &"
sleep 5

# Verificar se está rodando
echo "Verificando servidor..."
if docker exec "$CORE_CONTAINER" ss -tlnp | grep -q ":5201"; then
    echo "✓ Servidor escutando na porta 5201"
    docker exec "$CORE_CONTAINER" ss -tlnp | grep ":5201"
else
    echo "✗ Servidor NÃO está escutando!"
    echo "Log do servidor:"
    docker exec "$CORE_CONTAINER" cat /tmp/iperf3_server.log || echo "Sem log"
    echo ""
    echo "Processos iperf3:"
    docker exec "$CORE_CONTAINER" ps aux | grep iperf3
    exit 1
fi
echo ""

# 6. Teste simples uplink (sem UDP para começar)
echo "[6] Testando conexão TCP simples (UE -> 5GC)..."
echo "Comando: sudo ip netns exec ue1 iperf3 -c $CORE_IP -t $DURATION"
if sudo ip netns exec ue1 iperf3 -c $CORE_IP -t $DURATION; then
    echo ""
    echo "✓ Teste TCP uplink funcionou!"
else
    echo "✗ Teste TCP uplink falhou!"
fi
echo ""

# 7. Limpar
echo "[7] Limpando..."
docker exec "$CORE_CONTAINER" pkill -9 iperf3 || true

echo ""
echo "=== Teste Concluído ==="


