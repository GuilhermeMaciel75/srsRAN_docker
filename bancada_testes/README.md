# 📊 Bancada de Testes 5G srsRAN Split Architecture

Ferramenta automatizada para benchmarking de throughput em arquitetura split (DU/CU) do srsRAN.

## 🎯 O Que Foi Alterado

### Problema Original
- Script tentava usar **UDP** com altas taxas (10M, 20M, 50M)
- Servidor iperf3 em modo "one-off" não funcionava adequadamente
- Erro: `Resource temporarily unavailable`

### Solução Implementada
- Mudança para **TCP** (protocolo que funciona perfeitamente)
- 3 repetições para calcular média e desvio
- Duração de 20 segundos por teste
- Saída em JSON para análise automatizada
- Servidor iperf3 reiniciado entre cada teste

## 📁 Arquivos

```
bancada_testes/
├── run_benchmark.sh         # Script principal de benchmarking
├── test_quick.sh            # Teste rápido de conectividade
├── collect_metrics.py       # Coletor de métricas do DU (UDP 55555)
├── du_metrics.template.yml  # Template de configuração
└── results/                 # Resultados dos testes
    └── test_YYYYMMDD_HHMMSS/
        ├── uplink_test1.json
        ├── uplink_test2.json
        ├── uplink_test3.json
        ├── downlink_test1.json
        ├── downlink_test2.json
        ├── downlink_test3.json
        └── du_metrics.csv
```

## 🚀 Como Usar

### Pré-requisitos

1. **Infraestrutura rodando:**
   ```bash
   docker ps | grep -E "5gc|cu|du"
   # Deve mostrar: open5gs_5gc, oran_cu, oran_du
   ```

2. **UE conectado:**
   ```bash
   sudo ip netns exec ue1 ip addr show tun_srsue
   # Deve ter um IP 10.45.1.x
   ```

3. **Dependências:**
   ```bash
   # No host
   sudo apt install jq bc
   
   # iperf3 será instalado automaticamente nos containers
   ```

### Executar Benchmark Completo

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/bancada_testes

# Executar benchmark (3 testes de 20s cada direção)
./run_benchmark.sh
```

**Duração total:** ~4 minutos (6 testes x 20s + delays)

### Executar Teste Rápido

```bash
# Teste de conectividade (10 segundos)
./test_quick.sh
```

## 📊 Interpretando Resultados

### Durante a Execução

```
================================================================
Iniciando teste #1 - Throughput Máximo TCP
================================================================
[Uplink] Teste #1 (UE -> 5GC via DU/CU)...
✓ Servidor iperf3 rodando na porta 5201
✓ Uplink teste #1 concluído.
  Throughput (sender): 30.50 Mbps

[Downlink] Teste #1 (5GC -> UE via CU/DU)...
✓ Servidor iperf3 rodando na porta 5201
✓ Downlink teste #1 concluído.
  Throughput (receiver): 28.20 Mbps
```

### Ao Final

```
=== Análise Rápida ===
Uplink Teste #1: 30.50 Mbps
Uplink Teste #2: 31.20 Mbps
Uplink Teste #3: 30.80 Mbps
Downlink Teste #1: 28.20 Mbps
Downlink Teste #2: 29.10 Mbps
Downlink Teste #3: 28.50 Mbps

=== Médias ===
Uplink Médio: 30.83 Mbps (3 testes)
Downlink Médio: 28.60 Mbps (3 testes)
```

### Arquivos JSON

Cada teste gera um arquivo JSON com dados detalhados:

```bash
# Ver resumo de um teste
cat results/test_20251229_HHMMSS/uplink_test1.json | jq '.end.sum_sent'

# Extrair apenas o throughput
jq -r '.end.sum_sent.bits_per_second' results/test_*/uplink_test1.json
```

## 🔧 Personalização

### Mudar Duração dos Testes

Edite `run_benchmark.sh`:
```bash
DURATION=30  # 30 segundos por teste
```

### Mudar Número de Repetições

```bash
TESTS=("TCP" "TCP" "TCP" "TCP" "TCP")  # 5 repetições
```

### Adicionar Testes UDP (Experimental)

⚠️ **Nota:** UDP tem problemas de buffer no iperf3 dentro de containers.

Se quiser tentar:
```bash
# No loop principal, adicione:
iperf3 -c $CORE_IP -u -b 10M -t $DURATION -i 1 -J
```

## 📈 Métricas do DU

O script também coleta métricas do DU via UDP porta 55555:

```bash
# Ver métricas coletadas
cat results/test_*/du_metrics.csv
```

**Campos importantes:**
- `rnti`: ID do UE
- `cqi`: Channel Quality Indicator
- `dl_mcs`: Downlink Modulation and Coding Scheme
- `ul_mcs`: Uplink Modulation and Coding Scheme
- `dl_brate_kbps`: Taxa downlink
- `ul_brate_kbps`: Taxa uplink

## 🐛 Troubleshooting

### Problema: "Container não está rodando"
```bash
# Verificar containers
docker ps -a

# Iniciar 5GC se necessário
cd docker
docker-compose up -d 5gc
```

### Problema: "UE não está conectado"
```bash
# Verificar UE
sudo ip netns exec ue1 ip addr show tun_srsue

# Se não tiver IP, reconectar UE
sudo ./srsue ue_zmq.conf
```

### Problema: "Servidor iperf3 não está rodando"
```bash
# Limpar processos iperf3 antigos
docker exec open5gs_5gc pkill -9 iperf3

# Reiniciar benchmark
./run_benchmark.sh
```

### Problema: "jq: command not found"
```bash
# Instalar jq
sudo apt install jq bc
```

## 📝 Valores de Referência

Com ZMQ (simulação RF):
- **Uplink**: ~25-35 Mbps
- **Downlink**: ~25-32 Mbps

Fatores que afetam throughput:
- ✅ MCS (Modulation and Coding Scheme)
- ✅ CQI (Channel Quality)
- ✅ CPU load
- ✅ Configuração de banda (10 MHz no exemplo)
- ✅ ZMQ buffer sizes

## 🎓 Próximos Passos

1. **Análise de Latência:**
   ```bash
   sudo ip netns exec ue1 ping -c 100 10.53.1.2
   ```

2. **Testes com Múltiplos UEs:**
   - Conectar mais UEs
   - Executar testes paralelos

3. **Métricas PHY/MAC:**
   - Analisar `du_metrics.csv`
   - Correlacionar throughput com CQI/MCS

4. **Testes de Handover:**
   - Simular mobilidade entre DUs

## 📞 Suporte

Problemas ou dúvidas:
1. Verificar logs: `docker logs open5gs_5gc`
2. Verificar DU: `docker service logs oran_du_du`
3. Verificar CU: `docker service logs oran_cu_cu`

---

**Última atualização:** 29/12/2025
**Versão:** 2.0 (TCP otimizado)


