#!/bin/bash

echo "=== Teste de Conectividade ZMQ ==="
echo ""
echo "1. Verificando se 10.45.0.1:2001 está acessível do HOST:"
timeout 2 bash -c 'cat < /dev/null > /dev/tcp/10.45.0.1/2001' 2>/dev/null && echo "✓ HOST pode conectar em 10.45.0.1:2001" || echo "✗ HOST NÃO pode conectar em 10.45.0.1:2001"

echo ""
echo "2. Verificando se 172.18.0.1:2001 está acessível do HOST:"
timeout 2 bash -c 'cat < /dev/null > /dev/tcp/172.18.0.1/2001' 2>/dev/null && echo "✓ HOST pode conectar em 172.18.0.1:2001" || echo "✗ HOST NÃO pode conectar em 172.18.0.1:2001"

echo ""
echo "3. Testando do container DU (se estiver rodando):"
DU_CONTAINER=$(docker ps --format '{{.ID}}' --filter "name=du" | head -1)

if [ -n "$DU_CONTAINER" ]; then
  echo "   Container DU encontrado: $DU_CONTAINER"
  echo ""
  echo "   3a. Testando 10.45.0.1:2001 do container:"
  docker exec $DU_CONTAINER timeout 2 sh -c 'cat < /dev/null > /dev/tcp/10.45.0.1/2001' 2>/dev/null && echo "   ✓ CONTAINER pode conectar em 10.45.0.1:2001" || echo "   ✗ CONTAINER NÃO pode conectar em 10.45.0.1:2001"
  
  echo ""
  echo "   3b. Testando 172.18.0.1:2001 do container:"
  docker exec $DU_CONTAINER timeout 2 sh -c 'cat < /dev/null > /dev/tcp/172.18.0.1/2001' 2>/dev/null && echo "   ✓ CONTAINER pode conectar em 172.18.0.1:2001" || echo "   ✗ CONTAINER NÃO pode conectar em 172.18.0.1:2001"
  
  echo ""
  echo "   3c. Rotas do container:"
  docker exec $DU_CONTAINER ip route
else
  echo "   ✗ Container DU não está rodando"
fi

echo ""
echo "4. Porta 2001 está em uso?"
ss -tln | grep ":2001" && echo "✓ Porta 2001 está em LISTEN" || echo "✗ Porta 2001 NÃO está em uso"

