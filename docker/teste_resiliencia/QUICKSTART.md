# 🚀 Quickstart: Simulador de Falha e Recuperação CU

## Execução Rápida

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/teste_resiliencia
./simular_falha_cu.sh
```

## O que acontece?

### ⏱️ Cronograma (Total: ~2-3 minutos)

```
00:00 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Início
  │
  ├─ [10s]  🧹 Limpeza: Remove CU e DU existentes
  │
  ├─ [15s]  🌐 Core: Verifica/Inicia Open5GS
  │
  ├─ [15s]  📡 CU Up: Deploy + Conexão AMF
  │
  ├─ [15s]  📡 DU Up: Deploy + F1 Setup
  │
  ├─ [10s]  ✅ Infraestrutura Estável
  │
  ├─ [--]   💥 SIMULAÇÃO DE FALHA (kill CU)
  │
  ├─ [15s]  ♻️  Auto Recovery: Swarm recria CU
  │
  ├─ [15s]  🔄 Restart DU: Reconexão F1
  │
  ├─ [05s]  ✔️  Validação de Conexões
  │
  └─ [02s]  📊 Relatório Final
     │
02:30 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Fim
```

## Saída do Script

### 🎨 Interface Visual

O script usa cores e emojis para fácil identificação:

- 🔸 **Magenta**: Etapas principais
- ℹ️  **Azul**: Informações
- ✅ **Verde**: Sucesso
- ⚠️  **Amarelo**: Avisos
- ❌ **Vermelho**: Erros

### 📋 Etapas Executadas

1. **LIMPEZA DO AMBIENTE**
   ```
   [2025-12-19 01:30:00] ℹ️  Removendo stacks CU e DU existentes...
   [2025-12-19 01:30:02] ✅ Stack oran_cu removida
   [2025-12-19 01:30:04] ✅ Stack oran_du removida
   [2025-12-19 01:30:05] ✅ Ambiente limpo!
   ```

2. **VERIFICAÇÃO DO CORE NETWORK**
   ```
   [2025-12-19 01:30:10] ℹ️  Verificando Open5GS...
   [2025-12-19 01:30:12] ✅ Core Network já está rodando!
   [2025-12-19 01:30:13] ✅ AMF rodando em: 10.53.1.2
   ```

3. **INICIANDO CU**
   ```
   [2025-12-19 01:30:20] ℹ️  Deployando stack CU...
   [2025-12-19 01:30:25] ℹ️  Aguardando serviço oran_cu_cu estar pronto...
   [2025-12-19 01:30:30] ✅ Serviço oran_cu_cu está pronto!
   [2025-12-19 01:30:35] ✅ CU conectado ao AMF com sucesso!
   ```

4. **INICIANDO DU**
   ```
   [2025-12-19 01:30:40] ℹ️  Deployando stack DU...
   [2025-12-19 01:30:45] ℹ️  Aguardando serviço oran_du_du estar pronto...
   [2025-12-19 01:30:50] ✅ Serviço oran_du_du está pronto!
   [2025-12-19 01:30:52] ✅ Conexão F1 estabelecida: DU ↔ CU
   [2025-12-19 01:30:53] ✅ CU reconheceu conexão do DU!
   ```

5. **SIMULANDO FALHA**
   ```
   [2025-12-19 01:31:00] ⚠️  Matando container da CU para simular falha crítica...
   [2025-12-19 01:31:01] ❌ FALHA SIMULADA: CU foi terminada abruptamente!
   ```

6. **RECUPERAÇÃO AUTOMÁTICA**
   ```
   [2025-12-19 01:31:10] ℹ️  Docker Swarm tentará reiniciar o container automaticamente...
   [2025-12-19 01:31:20] ✅ CU recuperada automaticamente pelo Docker Swarm!
   [2025-12-19 01:31:25] ✅ CU reconectada ao AMF!
   ```

7. **REINICIANDO DU**
   ```
   [2025-12-19 01:31:30] ⚠️  DU não reconecta automaticamente à CU. Forçando restart...
   [2025-12-19 01:31:35] ℹ️  Aguardando DU reiniciar...
   [2025-12-19 01:31:45] ✅ Serviço oran_du_du está pronto!
   ```

8. **VERIFICAÇÃO**
   ```
   [2025-12-19 01:31:50] ℹ️  Verificando conexão F1 restabelecida...
   [2025-12-19 01:31:52] ✅ ✓ DU: F1 Setup completado
   [2025-12-19 01:31:53] ✅ ✓ CU: F1 Setup Request recebido
   ```

9. **RELATÓRIO FINAL**
   ```
   ╔════════════════════════════════════════════════════════════╗
   ║            RESULTADO DO TESTE DE RESILIÊNCIA              ║
   ╚════════════════════════════════════════════════════════════╝
   
   📊 Resumo da Execução:
   
     ✓ Core Network (AMF):      Operacional
     ✓ CU Recovery:             Sucesso
     ✓ CU → AMF Reconnection:   Estabelecida
     ✓ DU → CU F1 Connection:   Restabelecida
   
   ⏱️  Tempo Total de Recuperação: ~30-40 segundos
   ```

## Monitoramento Durante Execução

Você pode acompanhar os logs em tempo real em outro terminal:

```bash
# Terminal 1: Executar o script
./simular_falha_cu.sh

# Terminal 2: Monitorar CU
docker service logs oran_cu_cu -f

# Terminal 3: Monitorar DU
docker service logs oran_du_du -f
```

## Troubleshooting

### ❓ "Stack oran_cu não encontrada"
**Normal!** Significa que o ambiente está limpo e o script irá criar tudo do zero.

### ❓ "Core Network não está rodando"
O script tentará iniciar automaticamente. Se falhar:
```bash
cd ../open5gs
docker-compose up -d
```

### ❓ "Timeout aguardando serviço"
Verifique se as imagens estão disponíveis:
```bash
docker images | grep -E "uc|ud"
```

### ❓ "F1 Setup não completado"
Execute novamente o restart do DU:
```bash
docker service update --force oran_du_du
```

## Após o Teste

Os serviços permanecerão rodando. Para limpar:

```bash
# Remover apenas CU e DU
docker stack rm oran_cu oran_du

# Remover tudo incluindo Core
cd ../open5gs
docker-compose down
```

## Próximos Passos

Após o teste bem-sucedido, você pode:

1. **Conectar um UE real** usando o script `resilience_test_v3.sh`
2. **Monitorar métricas** no Grafana (porta 3000)
3. **Testar múltiplas falhas** executando o script repetidamente
4. **Automatizar** agendando com cron para testes periódicos

## Links Úteis

- 📖 [README Completo](./README.md)
- 🏗️ [Arquitetura e Troubleshooting](../wiki/ARQUITETURA_E_TROUBLESHOOTING.md)
- 🎮 [Console Interativo DU](../wiki/CONSOLE_INTERATIVO_GUIA.md)

