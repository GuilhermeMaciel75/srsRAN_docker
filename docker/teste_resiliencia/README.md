# Teste de Resiliência - srsRAN Split Architecture

Este diretório contém scripts para testar a resiliência da arquitetura split CU/DU do srsRAN utilizando Docker Swarm.

## 🚀 Uso Rápido

```bash
# Navegar até o diretório
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/teste_resiliencia

# Executar simulador automatizado (Recomendado)
./simular_falha_cu.sh

# Ou executar teste completo com UE
./resilience_test_v3.sh
```

**Tempo estimado:** 2-3 minutos para setup + falha + recuperação completa.

## 📦 Scripts Disponíveis

| Script | Descrição |
|--------|-----------|
| `simular_falha_cu.sh` | **🆕 Simulador Automatizado** - Setup completo + Falha + Recuperação |
| `resilience_test.sh` | V1 - Teste básico de failover CU/DU |
| `resilience_test_v2.sh` | V2 - Com Service Health Check inteligente |
| `resilience_test_v3.sh` | V3 - Com UE e validação de ping |

### ⭐ Novo: Simulador Automatizado (`simular_falha_cu.sh`)

Script completo para simular falha e recuperação da CU:
- ✅ Limpeza automática do ambiente
- ✅ Verificação e inicialização do Core Network
- ✅ Deploy automático de CU e DU
- ✅ Simulação de falha crítica na CU
- ✅ Monitoramento de recuperação automática
- ✅ Reinício inteligente do DU para reconexão
- ✅ Relatório completo com logs coloridos

### 🎯 Recomendado para Testes E2E: V3 (`resilience_test_v3.sh`)

O script V3 é o mais completo para validação end-to-end:
- Conexão de UE real via srsUE
- Teste de ping antes da falha
- Teste de ping após recuperação
- Validação completa do plano de dados

## 📋 Visão Geral

O teste simula cenários de falha na Central Unit (CU) e verifica a capacidade de recuperação automática da infraestrutura. Devido a uma **limitação conhecida do srsRAN**, a Distributed Unit (DU) não consegue reconectar automaticamente quando a CU é reiniciada, necessitando de um mecanismo de health check para forçar o reinício da DU.

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                        INFRAESTRUTURA                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐         ┌──────────────┐                    │
│   │   Open5GS    │◄────────│      CU      │                    │
│   │    (5GC)     │  NGAP   │   (Swarm)    │                    │
│   │  10.53.1.2   │         │   cu_f1      │                    │
│   └──────────────┘         └──────┬───────┘                    │
│                                   │                             │
│                                   │ F1AP                        │
│                                   │                             │
│                            ┌──────▼───────┐                    │
│                            │      DU      │                    │
│                            │   (Swarm)    │                    │
│                            │   du_f1      │                    │
│                            └──────────────┘                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Redes Docker

| Rede | Subnet | Propósito |
|------|--------|-----------|
| `docker_ran` | 10.53.1.0/24 | Comunicação com 5GC (NGAP) |
| `docker_f1` | 10.54.1.0/24 | Interface F1 entre CU e DU |

### Serviços

| Serviço | Imagem | Descrição |
|---------|--------|-----------|
| `5gc` | open5gs | Core 5G (AMF, SMF, UPF, etc.) |
| `oran_cu_cu` | guilhermemaciel75/uc:v0.0.10 | Central Unit |
| `oran_du_du` | guilhermemaciel75/ud:v0.0.11-metrics | Distributed Unit |

## 🔧 Pré-requisitos

1. **Docker** instalado e funcionando
2. **Docker Swarm** inicializado (o script inicializa automaticamente se necessário)
3. **Imagens Docker** disponíveis:
   - `guilhermemaciel75/uc:v0.0.10`
   - `guilhermemaciel75/ud:v0.0.11-metrics`

## 🚀 Como Usar

### 🆕 Simulador Automatizado (Recomendado)

O script `simular_falha_cu.sh` é um simulador completo e automatizado:

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/teste_resiliencia
./simular_falha_cu.sh
```

**O que o script faz automaticamente:**

| Etapa | Descrição | Tempo |
|-------|-----------|-------|
| 1️⃣ Limpeza | Remove CU e DU existentes | ~10s |
| 2️⃣ Core Network | Verifica/Inicia Open5GS AMF | ~15s |
| 3️⃣ Deploy CU | Inicia CU e conecta ao AMF | ~15s |
| 4️⃣ Deploy DU | Inicia DU e estabelece F1 | ~15s |
| 5️⃣ Status | Infraestrutura estável | ~10s |
| 6️⃣ Falha | Simula crash da CU | imediato |
| 7️⃣ Recuperação | Swarm recria CU automaticamente | ~15s |
| 8️⃣ Reconexão | Reinicia DU para F1 Setup | ~15s |
| 9️⃣ Validação | Verifica todas as conexões | ~5s |
| 🔟 Relatório | Status completo + logs | ~2s |

**Total:** ~2-3 minutos para ciclo completo

**Saída do Relatório:**
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

---

### 📜 Scripts Legados (V1, V2, V3)

Estes scripts requerem configuração manual de ambiente e argumentos.

### Dar permissão de execução

```bash
chmod +x resilience_test.sh
```

### Executar teste completo

```bash
./resilience_test.sh --full-test
# ou simplesmente:
./resilience_test.sh
```

### Apenas iniciar a infraestrutura (sem teste de falha)

```bash
./resilience_test.sh --start
```

### Verificar status atual

```bash
./resilience_test.sh --status
```

### Limpar todos os serviços

```bash
./resilience_test.sh --cleanup
```

### Iniciar monitoramento de saúde contínuo

```bash
./resilience_test.sh --health-check
```

### Simular falha da CU (infraestrutura já rodando)

```bash
./resilience_test.sh --simulate-cu-fail
```

### Reiniciar DU manualmente

```bash
./resilience_test.sh --restart-du
```

## 📝 Fluxo do Teste Completo

O teste `--full-test` executa os seguintes passos:

```
1. VERIFICAÇÃO INICIAL
   └── Verifica se Docker Swarm está ativo

2. LIMPEZA
   ├── Remove stack da DU (se existir)
   ├── Remove stack da CU (se existir)
   └── Para containers do 5GC (se existir)

3. INICIALIZAÇÃO DO 5G CORE
   ├── Executa docker compose up -d 5gc
   ├── Aguarda 30 segundos
   └── Verifica health check do Open5GS

4. INICIALIZAÇÃO DA CU
   ├── Deploy da stack via Docker Swarm
   ├── Aguarda serviço ficar saudável
   └── Verifica réplicas rodando

5. INICIALIZAÇÃO DA DU
   ├── Deploy da stack via Docker Swarm
   ├── Aguarda serviço ficar saudável
   └── Verifica conexão F1 com CU

6. SIMULAÇÃO DE FALHA DA CU
   ├── Identifica container da CU
   ├── Executa docker kill no container
   └── Aguarda 10 segundos

7. VERIFICAÇÃO DE RECUPERAÇÃO DA CU
   ├── Monitora criação de nova réplica pelo Swarm
   ├── Aguarda até 60 segundos (12 tentativas x 5s)
   └── Verifica se nova CU está rodando

8. REINÍCIO DA DU PARA RECONEXÃO
   ├── Executa docker service update --force
   ├── Aguarda nova instância inicializar
   └── Verifica conexão com nova CU
```

## ⚠️ Limitação do srsRAN

O srsRAN possui uma **limitação conhecida** onde a DU não consegue reconectar automaticamente à CU após uma falha/reinício da CU. Isso ocorre porque:

1. A conexão SCTP/F1AP é estabelecida na inicialização da DU
2. Quando a CU falha, a conexão é perdida
3. A DU não possui mecanismo de reconexão automática implementado

### Solução Implementada

O script implementa um **health check** que:

1. Monitora o estado da conexão DU-CU
2. Detecta quando há problemas de conexão
3. Força o reinício da DU usando `docker service update --force`
4. A nova instância da DU estabelece conexão com a nova CU

## 🔍 Monitoramento

### Health Check Contínuo

O modo `--health-check` executa um loop que:

- Verifica se CU está rodando
- Verifica se DU está rodando
- Verifica conexão F1 entre DU e CU
- Após 3 falhas consecutivas, reinicia a DU automaticamente

```bash
./resilience_test.sh --health-check
```

### Logs dos Serviços

```bash
# Logs da CU
docker service logs oran_cu_cu -f

# Logs da DU
docker service logs oran_du_du -f

# Logs do 5GC
docker logs open5gs_5gc -f
```

## 🛠️ Troubleshooting

### Problema: Redes não encontradas

```bash
# Verifique se o 5GC subiu corretamente (ele cria as redes)
docker network ls | grep docker_
```

### Problema: CU não conecta ao AMF

```bash
# Verifique se o 5GC está saudável
docker inspect --format='{{.State.Health.Status}}' open5gs_5gc

# Verifique logs do AMF
docker logs open5gs_5gc 2>&1 | grep -i amf
```

### Problema: DU não conecta à CU

```bash
# Verifique se a CU está acessível pela rede F1
docker exec $(docker ps -qf "name=oran_du") ping -c 3 cu_f1

# Verifique logs da DU
docker service logs oran_du_du --tail 100
```

### Problema: Swarm não está ativo

```bash
# Inicialize o Swarm
docker swarm init

# Se já for parte de um swarm como worker
docker swarm leave --force
docker swarm init
```

## 📊 Métricas e Observabilidade

O docker-compose inclui serviços de métricas (se habilitados):

- **InfluxDB**: Armazenamento de métricas
- **Grafana**: Visualização (porta 3300)
- **Metrics Server**: Coleta de métricas do gNB

## 🧪 Teste V3 - Com UE e Validação de Ping

### Pré-requisitos adicionais para V3

1. **srsUE instalado** (srsRAN_4G)
   ```bash
   # Se não estiver instalado, defina o caminho:
   export SRSUE_PATH=/caminho/para/srsue
   ```

2. **Executar como root** (necessário para namespaces de rede)

### Executar teste completo V3

```bash
sudo ./resilience_test_v3.sh --full-test
```

### Fluxo do teste V3

```
1. Limpa serviços existentes
2. Sobe 5G Core (Open5GS)
3. Sobe CU via Docker Swarm
4. Sobe DU via Docker Swarm
5. Configura namespace de rede para UE
6. Registra UE no core (IMSI: 001010123456780)
7. Inicia srsUE e aguarda attach
8. ✓ PING #1 - Antes da falha
9. Simula falha da CU (docker kill)
10. Aguarda Swarm recriar CU
11. Remove e recria DU
12. Reconecta UE
13. ✓ PING #2 - Após recuperação
14. Exibe resultado final
```

### Opções do V3

```bash
# Teste completo com UE
sudo ./resilience_test_v3.sh --full-test

# Iniciar infraestrutura com UE
sudo ./resilience_test_v3.sh --start-with-ue

# Apenas fazer ping do UE
sudo ./resilience_test_v3.sh --ping

# Iniciar/parar UE manualmente
sudo ./resilience_test_v3.sh --start-ue
sudo ./resilience_test_v3.sh --stop-ue

# Service Health com reconexão de UE
sudo ./resilience_test_v3.sh --service-health
```

### Configuração do UE

O script cria automaticamente o arquivo `ue_zmq.conf` com:

| Parâmetro | Valor |
|-----------|-------|
| IMSI | 001010123456780 |
| K | 00112233445566778899aabbccddeeff |
| OPC | 63BFA50EE6523365FF14C1F45F88737D |
| APN | srsapn |
| Banda | 3 (FDD) |
| ZMQ TX | tcp://*:2001 |
| ZMQ RX | tcp://127.0.0.1:2000 |

### Namespace de Rede

O UE opera em um namespace isolado (`ue1`):

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
│  │10.45.0.1 │           │         │           │10.45.x.x │  │
│  └──────────┘           │         │           └──────────┘  │
└─────────────────────────┘         └──────────────────────────┘
```

## 📁 Estrutura de Arquivos

```
docker/
├── teste_resiliencia/
│   ├── resilience_test.sh      # V1 - Script básico
│   ├── resilience_test_v2.sh   # V2 - Com Service Health
│   ├── resilience_test_v3.sh   # V3 - Com UE e Ping
│   ├── ue_zmq.conf             # Gerado automaticamente
│   └── README.md               # Esta documentação
├── docker-compose.yml        # Definição do 5GC e gNB monolítico
├── cu-ran-stack.yml          # Stack Swarm da CU
├── du-ran-stack.yml          # Stack Swarm da DU
├── cu/
│   ├── Dockerfile
│   ├── cu.template.yml
│   └── srscu                 # Binário da CU
└── du/
    ├── Dockerfile
    ├── du.template.yml
    └── srsdu                 # Binário da DU
```

## 🔐 Considerações de Segurança

- Os containers rodam em modo privilegiado (necessário para funcionalidades de rede)
- As redes são overlay para permitir comunicação entre nós do Swarm
- Os IPs são dinâmicos via DNS (aliases) para permitir failover

## 📚 Referências

- [srsRAN Project Documentation](https://docs.srsran.com/)
- [Open5GS Documentation](https://open5gs.org/open5gs/docs/)
- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)

