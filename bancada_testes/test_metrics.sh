#!/bin/bash

echo "=== Teste de Diagnóstico de Métricas DU ==="
echo ""

# Verificar configuração do DU
echo "[1] Verificando configuração de métricas no DU..."
DU_CONTAINER=$(docker ps --filter name=oran_du_du -q | head -1)
if [ -z "$DU_CONTAINER" ]; then
    echo "✗ ERRO: Container DU não encontrado!"
    exit 1
fi

echo "Container DU: $DU_CONTAINER"
echo ""

echo "[2] Configuração de métricas no du.yml:"
docker exec "$DU_CONTAINER" cat /du/du.yml 2>/dev/null | grep -A3 "metrics:"
echo ""

echo "[3] Interfaces de rede do DU:"
docker exec "$DU_CONTAINER" ip addr show | grep -E "^[0-9]+:|inet "
echo ""

echo "[4] Testando alcance do docker_gwbridge (172.18.0.1):"
docker exec "$DU_CONTAINER" sh -c "ip route | grep default"
echo ""

echo "[5] Verificando se algum processo está escutando na porta 55555 no host:"
ss -ulnp | grep 55555 || echo "Nenhum processo escutando na porta 55555"
echo ""

echo "[6] Iniciando captura de pacotes UDP na porta 55555..."
echo "Aguardando 30 segundos por pacotes..."
timeout 30 tcpdump -i any -n udp port 55555 -c 10 2>&1 &
TCPDUMP_PID=$!

sleep 2

echo ""
echo "[7] Iniciando coletor de métricas temporário..."
python3 /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/bancada_testes/collect_metrics.py \
    --port 55555 \
    --output /tmp/test_metrics.csv &
COLLECTOR_PID=$!

echo "Coletor iniciado (PID: $COLLECTOR_PID)"
echo "Aguardando métricas do DU por 30 segundos..."
sleep 30

echo ""
echo "[8] Parando coletor..."
kill $COLLECTOR_PID 2>/dev/null || true
wait $TCPDUMP_PID 2>/dev/null

echo ""
echo "[9] Métricas capturadas:"
if [ -f /tmp/test_metrics.csv ]; then
    wc -l /tmp/test_metrics.csv
    echo "Primeiras linhas:"
    head -5 /tmp/test_metrics.csv
else
    echo "✗ Nenhuma métrica capturada!"
fi

echo ""
echo "=== Diagnóstico Concluído ==="




