#!/bin/bash
set -e

# ===============================================================================
# Configuração
# ===============================================================================
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_BASE_DIR="$TEST_DIR/results"
DATE_STR=$(date "+%Y%m%d_%H%M%S")
CURRENT_RESULT_DIR="$RESULTS_BASE_DIR/test_$DATE_STR"
METRICS_SCRIPT="$TEST_DIR/collect_metrics.py"
DU_TEMPLATE="$TEST_DIR/du_metrics.template.yml"

# IP do 5GC na rede RAN (container open5gs_5gc)
CORE_IP="10.53.1.2"
CORE_CONTAINER="open5gs_5gc"

# IP do host na rede RAN (gateway) - onde o coletor de métricas vai escutar
# O DU consegue alcançar esse IP
HOST_METRICS_IP="10.53.1.1"
METRICS_PORT="55555"

# Durações e Taxas (TCP não precisa de rate limit, mas podemos testar diferentes durações)
DURATION=20
# Para TCP, vamos testar apenas throughput máximo
TESTS=("TCP" "TCP" "TCP")  # 3 repetições para média

mkdir -p "$CURRENT_RESULT_DIR"

echo "=== Bancada de Testes 5G srsRAN ==="
echo "Diretório de Resultados: $CURRENT_RESULT_DIR"

# ===============================================================================
# 1. Preparação do Ambiente
# ===============================================================================

# Verificar se container 5GC está rodando
if ! docker ps | grep -q "$CORE_CONTAINER"; then
    echo "Erro: Container $CORE_CONTAINER não está rodando."
    echo "Inicie o 5GC primeiro com: docker-compose up -d 5gc"
    exit 1
fi

# Instalar iperf3 no container 5GC se necessário
echo "[Setup] Verificando iperf3 no 5GC..."
if ! docker exec "$CORE_CONTAINER" which iperf3 &> /dev/null; then
    echo "[Setup] Instalando iperf3 no container 5GC..."
    docker exec "$CORE_CONTAINER" apt-get update
    docker exec "$CORE_CONTAINER" apt-get install -y iperf3
fi

# Instalar iperf3 no namespace do UE se necessário
echo "[Setup] Verificando iperf3 no UE..."
if ! sudo ip netns exec ue1 which iperf3 &> /dev/null; then
    echo "[Setup] Instalando iperf3 no namespace ue1..."
    sudo ip netns exec ue1 apt-get update
    sudo ip netns exec ue1 apt-get install -y iperf3
fi

# Obter IP do UE
echo "[Setup] Obtendo IP do UE..."
UE_IP=$(sudo ip netns exec ue1 ip addr show tun_srsue | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if [ -z "$UE_IP" ]; then
    echo "Erro: UE não parece estar conectado (sem IP na interface tun_srsue)."
    echo "Verifique se o UE está rodando: sudo ./srsue ue_zmq.conf"
    exit 1
fi
echo "UE IP: $UE_IP"

# ===============================================================================
# 3. Iniciar Coletor de Métricas
# ===============================================================================
echo "[Metrics] Iniciando coletor de métricas CSV..."
echo "Coletor escutando em $HOST_METRICS_IP:$METRICS_PORT"
# Kill any existing collector
pkill -f collect_metrics.py || true
python3 "$METRICS_SCRIPT" --port $METRICS_PORT --output "$CURRENT_RESULT_DIR/du_metrics.csv" &
METRICS_PID=$!
echo "Coletor rodando (PID: $METRICS_PID)"
sleep 2

# ===============================================================================
# 4. Executar Testes
# ===============================================================================

# Limpar processos antigos
docker exec "$CORE_CONTAINER" pkill -9 iperf3 || true
sleep 2

TEST_NUM=1
for TEST in "${TESTS[@]}"; do
    echo "================================================================"
    echo "Iniciando teste #$TEST_NUM - Throughput Máximo TCP"
    echo "================================================================"
    
    # --- UPLINK TEST (UE -> 5GC) ---
    echo "[Uplink] Teste #$TEST_NUM (UE -> 5GC via DU/CU)..."
    
    # Inicia servidor iperf3 no container 5GC em background
    echo "Iniciando servidor iperf3 no 5GC..."
    docker exec "$CORE_CONTAINER" bash -c "nohup iperf3 -s > /tmp/iperf3_server.log 2>&1 &"
    sleep 5
    
    # Verificar se servidor está escutando
    if docker exec "$CORE_CONTAINER" ss -tlnp | grep -q ":5201"; then
        echo "✓ Servidor iperf3 rodando na porta 5201"
    else
        echo "✗ ERRO: Servidor iperf3 não está rodando!"
        docker exec "$CORE_CONTAINER" cat /tmp/iperf3_server.log
        TEST_NUM=$((TEST_NUM + 1))
        continue
    fi

    echo "Executando: sudo ip netns exec ue1 iperf3 -c $CORE_IP -t $DURATION -i 1 -J"
    
    if sudo ip netns exec ue1 timeout $((DURATION + 10)) iperf3 -c $CORE_IP -t $DURATION -i 1 -J > "$CURRENT_RESULT_DIR/uplink_test${TEST_NUM}.json" 2> "$CURRENT_RESULT_DIR/uplink_test${TEST_NUM}.err"; then
        echo "✓ Uplink teste #$TEST_NUM concluído."
        # Extrair throughput médio (sender)
        AVG_BPS=$(jq -r '.end.sum_sent.bits_per_second // empty' "$CURRENT_RESULT_DIR/uplink_test${TEST_NUM}.json" 2>/dev/null)
        if [ ! -z "$AVG_BPS" ] && [ "$AVG_BPS" != "null" ]; then
            AVG_MBPS=$(echo "scale=2; $AVG_BPS / 1000000" | bc)
            echo "  Throughput (sender): $AVG_MBPS Mbps"
        else
            echo "  (Não foi possível extrair throughput do JSON)"
        fi
    else
        echo "✗ Uplink teste #$TEST_NUM falhou! Logs:"
        cat "$CURRENT_RESULT_DIR/uplink_test${TEST_NUM}.err"
    fi
    
    # Parar servidor
    docker exec "$CORE_CONTAINER" pkill -9 iperf3 || true
    sleep 5

    # --- DOWNLINK TEST (5GC -> UE) ---
    echo ""
    echo "[Downlink] Teste #$TEST_NUM (5GC -> UE via CU/DU)..."
    echo "Modo REVERSE: UE conecta e 5GC envia dados"
    
    # Inicia servidor iperf3 novamente
    echo "Iniciando servidor iperf3 no 5GC..."
    docker exec "$CORE_CONTAINER" bash -c "nohup iperf3 -s > /tmp/iperf3_server.log 2>&1 &"
    sleep 5
    
    # Verificar se servidor está escutando
    if docker exec "$CORE_CONTAINER" ss -tlnp | grep -q ":5201"; then
        echo "✓ Servidor iperf3 rodando na porta 5201"
    else
        echo "✗ ERRO: Servidor iperf3 não está rodando!"
        docker exec "$CORE_CONTAINER" cat /tmp/iperf3_server.log
        TEST_NUM=$((TEST_NUM + 1))
        continue
    fi

    echo "Executando: sudo ip netns exec ue1 iperf3 -c $CORE_IP -R -t $DURATION -i 1 -J"

    if sudo ip netns exec ue1 timeout $((DURATION + 10)) iperf3 -c $CORE_IP -R -t $DURATION -i 1 -J > "$CURRENT_RESULT_DIR/downlink_test${TEST_NUM}.json" 2> "$CURRENT_RESULT_DIR/downlink_test${TEST_NUM}.err"; then
        echo "✓ Downlink teste #$TEST_NUM concluído."
        # Extrair throughput médio (receiver, pois é reverse)
        AVG_BPS=$(jq -r '.end.sum_received.bits_per_second // empty' "$CURRENT_RESULT_DIR/downlink_test${TEST_NUM}.json" 2>/dev/null)
        if [ ! -z "$AVG_BPS" ] && [ "$AVG_BPS" != "null" ]; then
            AVG_MBPS=$(echo "scale=2; $AVG_BPS / 1000000" | bc)
            echo "  Throughput (receiver): $AVG_MBPS Mbps"
        else
            echo "  (Não foi possível extrair throughput do JSON)"
        fi
    else
        echo "✗ Downlink teste #$TEST_NUM falhou! Logs:"
        cat "$CURRENT_RESULT_DIR/downlink_test${TEST_NUM}.err"
    fi
    
    # Parar servidor
    docker exec "$CORE_CONTAINER" pkill -9 iperf3 || true
    sleep 5
    
    TEST_NUM=$((TEST_NUM + 1))
    echo ""
done

# ===============================================================================
# 5. Cleanup
# ===============================================================================
echo "=== Finalizando Testes ==="

# Parar coletor de métricas
kill $METRICS_PID 2>/dev/null || true
echo "Coletor de métricas parado."

# Parar servidores iperf3 no 5GC
docker exec "$CORE_CONTAINER" pkill iperf3 || true

echo "================================================================"
echo "Resultados salvos em: $CURRENT_RESULT_DIR"
echo "================================================================"
ls -lh "$CURRENT_RESULT_DIR"

echo ""
echo "=== Análise Rápida ==="

# Arrays para calcular médias
declare -a UL_VALUES
declare -a DL_VALUES

for i in {1..3}; do
    if [ -f "$CURRENT_RESULT_DIR/uplink_test${i}.json" ]; then
        UL_BPS=$(jq -r '.end.sum_sent.bits_per_second // empty' "$CURRENT_RESULT_DIR/uplink_test${i}.json" 2>/dev/null)
        if [ ! -z "$UL_BPS" ] && [ "$UL_BPS" != "null" ]; then
            UL_MBPS=$(echo "scale=2; $UL_BPS / 1000000" | bc)
            UL_VALUES+=($UL_MBPS)
            echo "Uplink Teste #$i: $UL_MBPS Mbps"
        fi
    fi
    if [ -f "$CURRENT_RESULT_DIR/downlink_test${i}.json" ]; then
        DL_BPS=$(jq -r '.end.sum_received.bits_per_second // empty' "$CURRENT_RESULT_DIR/downlink_test${i}.json" 2>/dev/null)
        if [ ! -z "$DL_BPS" ] && [ "$DL_BPS" != "null" ]; then
            DL_MBPS=$(echo "scale=2; $DL_BPS / 1000000" | bc)
            DL_VALUES+=($DL_MBPS)
            echo "Downlink Teste #$i: $DL_MBPS Mbps"
        fi
    fi
done

echo ""
echo "=== Médias ===" 
if [ ${#UL_VALUES[@]} -gt 0 ]; then
    UL_SUM=0
    for val in "${UL_VALUES[@]}"; do
        UL_SUM=$(echo "$UL_SUM + $val" | bc)
    done
    UL_AVG=$(echo "scale=2; $UL_SUM / ${#UL_VALUES[@]}" | bc)
    echo "Uplink Médio: $UL_AVG Mbps (${#UL_VALUES[@]} testes)"
fi

if [ ${#DL_VALUES[@]} -gt 0 ]; then
    DL_SUM=0
    for val in "${DL_VALUES[@]}"; do
        DL_SUM=$(echo "$DL_SUM + $val" | bc)
    done
    DL_AVG=$(echo "scale=2; $DL_SUM / ${#DL_VALUES[@]}" | bc)
    echo "Downlink Médio: $DL_AVG Mbps (${#DL_VALUES[@]} testes)"
fi

echo ""
echo "=== Concluído com Sucesso! ==="

