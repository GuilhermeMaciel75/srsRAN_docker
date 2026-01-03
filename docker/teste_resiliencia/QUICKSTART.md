# 🚀 Quickstart: Simuladores de Falha e Recuperação CU

## 📌 Dois Modos Disponíveis

### 1️⃣ Modo Básico (sem UE)
Teste rápido de resiliência da infraestrutura CU/DU.

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/teste_resiliencia
./simular_falha_cu.sh
```

### 2️⃣ Modo Completo (com UE) - **Recomendado** 🔥
Teste end-to-end incluindo UE real com validação de conectividade.

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/teste_resiliencia
sudo ./simular_falha_cu_com_ue.sh
```

**⚠️ Nota:** O modo com UE requer privilégios root e srsRAN 4G compilado.

---

## ✅ Pré-requisitos

### Para Modo Básico
- Docker instalado e rodando
- Docker Swarm inicializado

### Para Modo Completo (adicionais)
- **srsRAN 4G** compilado em: `/home/guilhermemaciel/Documentos/srsRAN/srsRAN_4G/build/srsue/src/srsue`
- Privilégios **root/sudo**

**Compilar srsRAN 4G (se necessário):**
```bash
cd /home/guilhermemaciel/Documentos/srsRAN/
git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G
mkdir build && cd build
cmake ../
make -j$(nproc)
```

---

## ⏱️ Cronogramas

### Modo Básico (~2-3 minutos)

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

### Modo Completo com UE (~3-4 minutos)

```
00:00 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Início
  │
  ├─ [10s]  🧹 Limpeza: Remove CU, DU e namespace UE
  │
  ├─ [15s]  🌐 Core: Verifica/Inicia Open5GS
  │
  ├─ [15s]  📡 CU Up: Deploy + Conexão AMF
  │
  ├─ [15s]  📡 DU Up: Deploy + F1 Setup
  │
  ├─ [05s]  🔧 Setup: Namespace + veth pair
  │
  ├─ [20s]  📱 UE Connect: srsUE attach + PDU session
  │
  ├─ [05s]  🏓 Ping #1: Teste baseline (UE → Core)
  │
  ├─ [10s]  ✅ Infraestrutura Estável
  │
  ├─ [--]   💥 SIMULAÇÃO DE FALHA (kill CU)
  │
  ├─ [15s]  ♻️  Auto Recovery: Swarm recria CU
  │
  ├─ [15s]  🔄 Restart DU: Reconexão F1
  │
  ├─ [20s]  📱 UE Reconnect: Novo attach
  │
  ├─ [05s]  🏓 Ping #2: Validação pós-recuperação
  │
  ├─ [05s]  ✔️  Validação de Conexões
  │
  └─ [02s]  📊 Relatório Final
     │
03:30 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ Fim
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

1. **Conectar um UE real** usando `simular_falha_cu_com_ue.sh` (✨ Novo!)
2. **Monitorar métricas** no Grafana (porta 3000)
3. **Testar múltiplas falhas** executando o script repetidamente
4. **Automatizar** agendando com cron para testes periódicos

---

## 🔥 Modo Completo com UE - Guia Detalhado

### Pré-requisitos Adicionais

```bash
# 1. Verificar se srsUE existe
ls -lh /home/guilhermemaciel/Documentos/srsRAN/srsRAN_4G/build/srsue/src/srsue

# 2. Se não existir, compilar srsRAN 4G
cd /home/guilhermemaciel/Documentos/srsRAN/
git clone https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G
mkdir build && cd build
cmake ../
make -j$(nproc)
```

### Execução

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/teste_resiliencia
sudo ./simular_falha_cu_com_ue.sh
```

### O Que É Diferente?

O script com UE adiciona:

1. ✅ **Namespace de rede isolado** (`ue1`)
2. ✅ **Conexão real de UE** via srsUE + ZMQ
3. ✅ **Teste de PING #1** (baseline antes da falha)
4. ✅ **Reconexão automática do UE** após recuperação
5. ✅ **Teste de PING #2** (validação pós-recuperação)
6. ✅ **UE permanece conectado** para testes manuais

### Fluxo Completo

```
Fase 1: SETUP
├─ Limpar ambiente
├─ Iniciar Core (5gc)
├─ Iniciar CU
├─ Iniciar DU
├─ Criar namespace ue1
└─ Conectar UE → PDU Session OK

Fase 2: BASELINE
└─ Ping UE → Core: 10.45.0.1 ✓

Fase 3: FALHA
└─ Kill CU container

Fase 4: RECUPERAÇÃO
├─ Swarm recria CU
├─ Restart DU forçado
└─ CU-AMF + DU-CU reconectados

Fase 5: RECONEXÃO UE
├─ Parar srsUE anterior
├─ Reiniciar srsUE
└─ Novo attach → IP pode mudar

Fase 6: VALIDAÇÃO
├─ Ping UE → Core: 10.45.0.1 ✓
└─ Relatório final com status UE
```

### Informações do UE

| Parâmetro | Valor |
|-----------|-------|
| IMSI | 001010123456780 |
| K | 00112233445566778899aabbccddeeff |
| OPC | 63BFA50EE6523365FF14C1F45F88737D |
| APN | srsapn |
| Banda | 3 (NR) |
| ZMQ TX | tcp://*:2001 |
| ZMQ RX | tcp://127.0.0.1:2000 |

### Comandos Úteis

```bash
# Monitorar logs do UE em tempo real
tail -f /tmp/ue_run.log

# Ver IP atribuído ao UE
sudo ip netns exec ue1 ip addr show tun_srsue

# Testar ping manualmente
sudo ip netns exec ue1 ping -c 4 10.45.0.1

# Verificar rotas no namespace
sudo ip netns exec ue1 ip route

# Entrar no namespace para debug
sudo ip netns exec ue1 bash

# Capturar tráfego do UE
sudo ip netns exec ue1 tcpdump -i tun_srsue -w /tmp/ue_capture.pcap

# Verificar processos do srsUE
ps aux | grep srsue
```

### Troubleshooting Específico

#### ❓ UE não conecta

1. Verificar porta ZMQ do DU:
   ```bash
   ss -tuln | grep 2000
   # Esperado: 0.0.0.0:2000 LISTEN
   ```

2. Verificar subscriber cadastrado:
   - Abrir http://localhost:9999
   - Login: admin / admin
   - Verificar IMSI: 001010123456780

3. Ver últimas linhas do log:
   ```bash
   tail -50 /tmp/ue_run.log
   ```

#### ❓ Ping falha

1. Verificar interface TUN existe:
   ```bash
   sudo ip netns exec ue1 ip link show tun_srsue
   ```

2. Verificar IP foi atribuído:
   ```bash
   sudo ip netns exec ue1 ip addr show tun_srsue
   # Esperado: inet 10.45.x.x/24
   ```

3. Testar conectividade namespace ↔ host:
   ```bash
   sudo ip netns exec ue1 ping -c 2 10.45.254.1
   ```

#### ❓ "Namespace já existe"

Limpar manualmente:
```bash
sudo ip netns del ue1
sudo ip link del veth0
```

### Limpeza Manual

Se precisar limpar o ambiente:

```bash
# Parar UE
sudo pkill -f "srsue.*ue_zmq"

# Remover namespace
sudo ip netns del ue1

# Remover veth
sudo ip link del veth0 2>/dev/null

# Remover stacks
docker stack rm oran_cu oran_du

# Parar Core (opcional)
cd ../
docker compose down 5gc
```

### UE Fica Conectado

Se o teste passar, o UE permanece conectado:

```
✅ UE permanecerá conectado para testes adicionais.
⚠️  Pressione Ctrl+C para parar o UE e limpar o ambiente

# Você pode então executar testes manuais em outro terminal
```

Experimente:
- Ping contínuo: `sudo ip netns exec ue1 ping 8.8.8.8`
- iPerf: `sudo ip netns exec ue1 iperf3 -c <server>`
- HTTP: `sudo ip netns exec ue1 curl http://example.com`

**Quando terminar, pressione Ctrl+C** no terminal do script para limpeza automática.

## Links Úteis

- 📖 [README Completo](./README.md)
- 🏗️ [Arquitetura e Troubleshooting](../wiki/ARQUITETURA_E_TROUBLESHOOTING.md)
- 🎮 [Console Interativo DU](../wiki/CONSOLE_INTERATIVO_GUIA.md)

