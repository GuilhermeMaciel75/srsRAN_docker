# 🎯 Guia Rápido: Console Interativo do srsRAN DU no Docker

## ❌ O Problema

Quando você faz `docker attach`, cai no shell do container (root@...:/du#) e **NÃO** no console do srsRAN onde você pode pressionar `t` para ver métricas.

**Causa**: O Dockerfile roda o DU em **background** com `&`:
```dockerfile
CMD [...&& /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]
                                    ↑
                            Roda em background!
```

## ✅ A Solução

Fazer o DU rodar em **foreground** (sem `&`):

```dockerfile
CMD [...&& exec /du/srsdu -c /du/du.yml"]
           ↑
    Roda em foreground!
```

---

## 📝 Passo a Passo

### **1. Editar o Dockerfile**

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/du
nano Dockerfile
```

**Trocar a linha 19 de:**
```dockerfile
CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && /du/srsdu -c /du/du.yml & tail -f /tmp/du.log"]
```

**Para:**
```dockerfile
CMD ["/bin/sh", "-c", "envsubst < /du/du.template.yml > /du/du.yml && exec /du/srsdu -c /du/du.yml"]
```

### **2. Rebuild a Imagem**

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker/du
docker build -t guilhermemaciel75/ud:v0.0.7-interactive .
```

### **3. Parar o Serviço Atual**

```bash
docker service rm oran_du_du
```

### **4. Atualizar o Stack File**

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker
nano du-ran-stack.yml
```

Mudar a linha `image:` para:
```yaml
image: guilhermemaciel75/ud:v0.0.7-interactive
```

### **5. Redeploy**

```bash
docker stack deploy -c du-ran-stack.yml oran_du
```

### **6. Aguardar Inicialização**

```bash
# Aguardar ~20 segundos
sleep 20

# Verificar se está rodando
docker ps | grep oran_du
```

### **7. Conectar ao Console** 🎉

```bash
# Encontrar o container
DU_CONTAINER=$(docker ps -q --filter "name=oran_du" | head -1)

# Attach
docker attach $DU_CONTAINER
```

**Agora você verá**:
```
--== srsRAN DU (commit ...) ==--
...
Cell pci=1, bw=20 MHz, ...
==== DU started ===
Type <h> to view help
```

**Pressione `t` ou `T`** → Verá as métricas! 📊

---

## 🎮 Comandos no Console

Após conectar com `docker attach`:

| Tecla | Função |
|-------|--------|
| `t` ou `T` | **Toggle métricas** (o que você quer!) |
| `h` | Mostrar help |
| `q` | **QUIT** (para o DU - **NÃO USE!**) |
| `Ctrl+P` + `Ctrl+Q` | **Sair sem parar o container** ✅ |

---

## 📊 Métricas Esperadas

Quando pressionar `T`:

```
       |--------------------DL---------------------|-------------------------UL------------------------------
pci rnti | cqi  ri  mcs  brate   ok  nok  (%)  dl_bs | pusch  rsrp  mcs  brate   ok  nok  (%)    bsr     ta  phr
  1 4601 |  15 1.0   27   686k  119    0   0%      0 |  32.7 -12.4   28   236k   44    0   0%      0   -56n   17
```

### Interpretação:
- **CQI=15**: Qualidade máxima! 
- **MCS=27/28**: Modulação alta (256-QAM)
- **RSRP=-12.4 dBm**: Sinal muito forte
- **Bitrate DL/UL**: ~700 Kbps / ~240 Kbps
- **ok=119, nok=0**: 100% de sucesso ✅

---

## 🚀 Script Automatizado

Use o script criado:

```bash
cd /home/guilhermemaciel/Documentos/srsRAN/srsRAN_split/docker
chmod +x rebuild_du_interactive.sh
./rebuild_du_interactive.sh
```

Ele faz tudo automaticamente:
1. ✅ Para o serviço
2. ✅ Rebuild da imagem
3. ✅ Redeploy
4. ✅ Pergunta se quer conectar

---

## ⚠️ Importante

### Para SAIR do console sem parar o DU:
**Pressione**: `Ctrl+P` e depois `Ctrl+Q`

### **NÃO** pressione:
- ❌ `Ctrl+C` → Para o DU!
- ❌ `q` → Para o DU!
- ❌ `Ctrl+D` → Para o DU!

---

## 🔄 Diferenças: Versão Antiga vs Nova

| Aspecto | Versão Antiga (Background) | Versão Nova (Foreground) |
|---------|---------------------------|--------------------------|
| Console interativo | ❌ Não funciona | ✅ Funciona |
| Pressionar `t` | ❌ Não responde | ✅ Mostra métricas |
| `docker attach` | Shell (/bin/sh) | Console do srsRAN |
| Logs em arquivo | ✅ `/tmp/du.log` | ❌ Só stdout |
| `docker logs` | Limpo (só tail) | Verboso (tudo) |

---

## 🐛 Troubleshooting

### Problema: Ainda cai no shell (root@...:/du#)

**Causa**: Imagem antiga ainda em cache

**Solução**:
```bash
# Forçar remoção da imagem antiga
docker rmi guilhermemaciel75/ud:v0.0.6
docker rmi guilhermemaciel75/ud:v0.0.7-interactive

# Rebuild sem cache
docker build --no-cache -t guilhermemaciel75/ud:v0.0.7-interactive .
```

### Problema: Container sai após attach

**Causa**: Pressionou `Ctrl+C` ou `q`

**Solução**: Redeploy e use `Ctrl+P` + `Ctrl+Q` para sair

### Problema: Não mostra métricas ao pressionar `t`

**Causa 1**: Nenhum UE conectado
- **Solução**: Conectar o UE primeiro

**Causa 2**: Ainda está no shell, não no console do DU
- **Solução**: Verificar se o CMD do Dockerfile foi corrigido

---

## 📚 Referência Rápida

```bash
# Ver containers rodando
docker ps | grep oran_du

# Ver logs (muito verboso agora!)
docker logs $(docker ps -q --filter "name=oran_du" | head -1)

# Attach ao console
docker attach $(docker ps -q --filter "name=oran_du" | head -1)

# Sair do console (sem parar)
# Pressione: Ctrl+P depois Ctrl+Q

# Restart do serviço
docker service update --force oran_du_du
```

---

**Criado por**: Assistente AI  
**Data**: 12 de Novembro de 2025  
**Versão**: 1.0



