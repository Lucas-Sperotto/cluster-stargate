# Guia de instalação e implantação — Diário de Dor no `stargate-master`

**Servidor:** Dell PowerEdge 2950  
**Hostname:** `stargate-master`  
**Administrador:** `sperotto`  
**Sistema operacional atual:** Ubuntu Server 26.04.1 LTS (Resolute)  
**Ambiente pretendido:** laboratório / homologação privada / intranet  
**Rede principal:** `enp5s0` — DHCP — rede observada `10.28.15.0/24`  
**Segunda interface:** `enp9s0` — reservada para a futura rede privada do cluster  
**Armazenamento:** `/` ~100 GB, `/srv` ~400 GB, ~55 GB livres no LVM  
**Projeto:** `Lucas-Sperotto/diario-de-dor-platform`  
**Versão do projeto na elaboração deste guia:** `0.4.0-rc.1`

---

## 0. Objetivo e regras deste roteiro

Este documento começa **do estado atual do servidor recém-instalado** e termina com o
**Diário de Dor acessível pela rede interna**, usando Docker Compose.

O ambiente deste roteiro é de **homologação com dados sintéticos**.

> **NÃO utilizar dados reais de pacientes, profissionais, instituições, familiares ou
> qualquer informação identificável.**
>
> O próprio projeto classifica a versão atual como Release Candidate para homologação
> privada com dados sintéticos. O uso com dados reais está fora do escopo atual até
> revisão ética, jurídica e de segurança.

### Arquitetura usada neste guia

```text
Computador/celular na rede UNEMAT
              │
              │ HTTP — intranet
              ▼
      stargate-master
      10.28.15.x
              │
      ┌───────┼─────────┐
      │       │         │
      ▼       ▼         ▼
    :8080   :8000     :8025
     Web     API      MailHog
      │       │
      │       ├──────────────┐
      │       │              │
      │       ▼              ▼
      │   PostgreSQL       Redis
      │   somente Docker   somente Docker
      │
      └─ frontend estático
```

PostgreSQL e Redis **não terão portas publicadas no host**.

---

# PARTE I — Validar e corrigir a instalação-base

## 1. Conferir identidade do servidor

Execute:

```bash
hostnamectl
```

### O que o comando faz

- `hostnamectl` exibe o hostname, sistema operacional, kernel, arquitetura e hardware.
- O hostname esperado é `stargate-master`.

Verifique também:

```bash
cat /etc/os-release
```

### Explicação

- `cat` mostra o conteúdo de um arquivo.
- `/etc/os-release` contém a identificação da distribuição Linux.
- O sistema esperado neste servidor é Ubuntu 26.04.1 LTS ou uma atualização posterior
  da mesma série 26.04 LTS.

---

## 2. Conferir os pontos de montagem

```bash
df -hT
```

### Explicação linha a linha

- `df` significa *disk free* e mostra o uso dos sistemas de arquivos.
- `-h` apresenta tamanhos em GB/MB, em vez de blocos.
- `-T` mostra também o tipo de filesystem.

Deve existir aproximadamente:

```text
/       ~100 GB   ext4
/boot     ~2 GB   ext4
/srv     ~400 GB  ext4
```

Confira a estrutura de blocos:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

### Explicação

- `lsblk` lista discos, partições e volumes.
- `-o` define exatamente quais colunas serão exibidas.
- `NAME`: nome do dispositivo.
- `SIZE`: tamanho.
- `TYPE`: disco, partição ou LVM.
- `FSTYPE`: tipo de filesystem.
- `MOUNTPOINTS`: local onde está montado.

---

# PARTE II — Verificar a configuração de rede feita anteriormente

> **IMPORTANTE PARA OS ALUNOS**
>
> A configuração do Netplan já foi alterada pelo administrador no dia anterior.
> **Não editem o Netplan nesta etapa.** O objetivo aqui é somente confirmar que
> a configuração continua correta depois da reinicialização.
>
> Se qualquer resultado for diferente do esperado, parem e mostrem a saída ao
> professor antes de usar `nano`, `netplan apply`, `ip addr add`, `ip route add`
> ou qualquer outro comando que altere a rede.

---

## 3. Identificar os arquivos Netplan existentes

Execute:

```bash
ls -lah /etc/netplan/
```

### O que este comando faz

- `ls` lista arquivos;
- `-l` mostra detalhes;
- `-a` inclui arquivos ocultos;
- `-h` apresenta tamanhos de forma legível;
- `/etc/netplan/` é o diretório onde o Ubuntu guarda a configuração persistente
  das interfaces de rede.

Agora mostre o conteúdo dos arquivos YAML:

```bash
sudo cat /etc/netplan/*.yaml
```

### O que deve ser observado

Procurem as interfaces:

```text
enp5s0
enp9s0
```

A interface `enp5s0` é a conexão com a rede institucional.

A interface `enp9s0` está reservada para a futura rede privada do cluster e,
enquanto estiver sem cabo, deve estar configurada de forma que **não impeça o
boot do servidor**.

No arquivo alterado anteriormente deve existir configuração equivalente a:

```yaml
enp9s0:
  optional: true
```

O restante do arquivo pode variar de acordo com o instalador. **Não substituam
o arquivo apenas para fazê-lo ficar visualmente igual a este guia.**

---

## 4. Validar a sintaxe do Netplan sem alterar a rede

Execute:

```bash
sudo netplan generate
```

### Explicação

`netplan generate` lê os arquivos YAML e tenta gerar a configuração que será
usada pelo backend de rede. Ele é uma boa verificação de sintaxe porque **não
precisa trocar a conectividade atual**.

### Resultado esperado

Nenhum erro.

Se aparecer mensagem de erro com linha/coluna do YAML, parem e mostrem a saída
ao professor.

---

## 5. Conferir o estado resumido das interfaces

Execute:

```bash
ip -br link
```

### Explicação

- `ip` é a ferramenta moderna de configuração/diagnóstico de rede;
- `-br` significa *brief*, ou seja, saída resumida;
- `link` mostra o estado físico/lógico das interfaces.

Depois:

```bash
ip -br addr
```

### Explicação

Este segundo comando mostra também os endereços IP associados a cada interface.

### Esperado

Conceitualmente:

```text
enp5s0   UP             10.28.15.x/24 ...
enp9s0   DOWN/no-carrier ou equivalente
```

O número final do IP de `enp5s0` é recebido por DHCP e pode mudar.

**Não assumam que o IP antigo ainda é válido.**

---

## 6. Conferir a rota padrão

Execute:

```bash
ip route
```

### O que procurar

Deve existir uma rota parecida com:

```text
default via 10.28.15.1 dev enp5s0 ...
```

Isso significa que o tráfego destinado a outras redes utiliza `enp5s0`.

Confira também o endereço IPv4 atual da interface:

```bash
ip -4 -o addr show dev enp5s0
```

---

## 7. Conferir DNS

Execute:

```bash
resolvectl status
```

Depois faça um teste de resolução:

```bash
getent hosts github.com
```

### Explicação

- `resolvectl status` mostra quais servidores DNS estão sendo utilizados;
- `getent hosts github.com` pergunta ao sistema operacional qual IP corresponde
  ao nome `github.com`.

Se o segundo comando retornar um ou mais endereços, a resolução de nomes está
funcionando.

---

## 8. Conferir conectividade sem depender de ICMP externo

Primeiro teste o gateway conhecido da rede:

```bash
ping -c 4 10.28.15.1
```

### Explicação

- `ping` testa comunicação IP;
- `-c 4` envia quatro pacotes e termina.

Depois teste HTTPS:

```bash
curl -I https://github.com
```

### Por que usamos também `curl`

Algumas redes bloqueiam `ping` para a Internet, mas permitem HTTPS. Portanto um
`ping` externo falhar não significa necessariamente que a Internet está
indisponível.

O `curl` deve retornar cabeçalhos HTTP.

---

## 9. Conferir se a interface opcional não está causando falha de boot

Execute:

```bash
systemctl --failed
```

Depois:

```bash
systemctl status systemd-networkd-wait-online.service --no-pager
```

### Resultado esperado

O importante é que `systemd-networkd-wait-online.service` **não esteja em estado
failed por causa de `enp9s0` sem cabo**.

Também confira:

```bash
networkctl list
```

A interface `enp9s0` estar `no-carrier`, `off` ou equivalente é aceitável neste
momento.

---

## 10. Registrar o estado atual antes de continuar

Execute:

```bash
echo "===== HOST ====="
hostnamectl
echo
echo "===== INTERFACES ====="
ip -br addr
echo
echo "===== ROTAS ====="
ip route
echo
echo "===== FALHAS SYSTEMD ====="
systemctl --failed
```

### Por que fazemos isso

Este é um **checkpoint**. Se algo der errado nas etapas seguintes, teremos um
registro do estado conhecido antes de instalar Docker e aplicações.

Depois de confirmar que:

- `enp5s0` possui IPv4 institucional;
- existe rota padrão por `enp5s0`;
- DNS funciona;
- `enp9s0` não bloqueia o boot;
- não há falha grave do systemd;

podem seguir para a Parte III.

---

# PARTE III — Atualizar o sistema

> **REVISÃO OPERACIONAL — 10/09/2026**
>
> A partir desta parte, este guia foi atualizado para o servidor `stargate-master`
> como **servidor multipropósito**, e não apenas como servidor do Diário de Dor.
>
> Princípios adotados:
>
> - `/srv` é a área compartilhada de infraestrutura do servidor;
> - cada sistema terá seu próprio diretório, projeto Docker, volumes e backups;
> - o Docker usa um único `data-root` compartilhado em `/srv/docker/data-root`;
> - cada projeto Docker deve possuir nome próprio e portas sem conflito;
> - PostgreSQL, Redis e bancos equivalentes não devem ser publicados na LAN;
> - o Diário de Dor usa o `compose.intranet.yaml` **versionado no repositório**;
> - não criar manualmente outro `compose.intranet.yaml`;
> - o `.env` do Diário de Dor deve ser criado pelo script versionado
>   `scripts/prepare_intranet_env.sh`;
> - o código validado para esta instalação é
>   `main@d27826040891c28f1ce66d13f5d7050738084538`;
> - como o GitHub Actions está temporariamente sem runners por cota, a validação
>   será reproduzida localmente com `scripts/manual_quality_gate.sh`;
> - usar apenas dados sintéticos nesta fase.
>
> O relatório `relatorio_stargate_master_poweredge2950_v3.md`, do repositório
> `Lucas-Sperotto/cluster-stargate`, registra que o PowerEdge 2950 possui apenas
> cerca de 4 GiB de RAM e deve ser tratado como servidor de laboratório. Por isso,
> builds serão executados de forma sequencial e será verificada a existência de swap.

---

## 8. Atualizar o índice de pacotes

```bash
sudo apt update
```

### O que faz

- consulta os repositórios configurados;
- atualiza a lista de versões disponíveis;
- não instala atualizações ainda.

---

## 9. Atualizar os pacotes instalados

```bash
sudo apt full-upgrade -y
```

Depois:

```bash
sudo apt autoremove -y
```

Depois:

```bash
sudo apt clean
```

Confira se o sistema pede reinicialização:

```bash
if [ -f /var/run/reboot-required ]; then
  echo "REINICIALIZAÇÃO NECESSÁRIA"
  cat /var/run/reboot-required
else
  echo "Nenhuma reinicialização obrigatória indicada."
fi
```

Se for indicada:

```bash
sudo reboot
```

Após o servidor voltar, entre novamente por SSH e confira:

```bash
hostnamectl
```

```bash
uname -a
```

```bash
systemctl --failed
```

---

# PARTE IV — Instalar ferramentas básicas do host

## 10. Ferramentas gerais

```bash
sudo apt install -y \
  ca-certificates \
  curl \
  wget \
  git \
  vim \
  nano \
  htop \
  tree \
  unzip \
  zip \
  rsync \
  jq \
  tmux \
  screen \
  acl \
  bash-completion \
  gnupg \
  openssl
```

### Para que servem

- `ca-certificates`: certificados HTTPS;
- `curl` e `wget`: testes e downloads;
- `git`: versionamento;
- `vim` e `nano`: edição;
- `htop`: CPU/RAM/processos;
- `tree`: árvore de diretórios;
- `zip`/`unzip`: arquivos compactados;
- `rsync`: cópia/sincronização;
- `jq`: leitura de JSON;
- `tmux`/`screen`: sessões persistentes;
- `acl`: permissões avançadas;
- `bash-completion`: autocompletar;
- `gnupg` e `openssl`: chaves, assinaturas e geração de segredos.

---

## 11. Ferramentas de rede, hardware e diagnóstico

```bash
sudo apt install -y \
  dnsutils \
  net-tools \
  ethtool \
  smartmontools \
  ipmitool \
  lsscsi \
  lm-sensors \
  sysstat \
  iptables \
  postgresql-client
```

`postgresql-client` é apenas ferramenta administrativa do host. O PostgreSQL
do Diário de Dor continuará dentro do Docker.

Ative o `sysstat`:

```bash
sudo systemctl enable --now sysstat
```

Valide:

```bash
systemctl status sysstat --no-pager
```

---

## 12. Python e ferramentas de compilação

```bash
sudo apt install -y \
  build-essential \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  pkg-config
```

### Regra do servidor multipropósito

Esses pacotes são ferramentas genéricas do host.

**Não instalar diretamente no Ubuntu**, salvo necessidade documentada:

- PostgreSQL Server;
- Redis Server;
- MySQL Server;
- MongoDB Server;
- Django/FastAPI globalmente;
- dependências Python de cada aplicação;
- dependências específicas de OCR ou IA.

Esses componentes devem preferencialmente ficar nos containers de cada projeto.

---

## 13. Instalar Node.js/npm para reproduzir o gate do projeto

O CI do Diário de Dor utiliza Node.js 22. O Ubuntu Server 26.04 fornece Node.js 22
nos repositórios da distribuição.

```bash
sudo apt install -y nodejs npm
```

Confira:

```bash
node --version
```

```bash
npm --version
```

Para esta versão do guia, espera-se Node.js principal `v22.x`.

---

## 14. Instalar microcódigo Intel

```bash
sudo apt install -y intel-microcode
```

Confira:

```bash
test -f /var/run/reboot-required && cat /var/run/reboot-required || true
```

Se houver indicação:

```bash
sudo reboot
```

Depois:

```bash
grep -m1 microcode /proc/cpuinfo
```

```bash
sudo dmesg | grep -i microcode | tail -n 20
```

O servidor continua classificado como laboratório/homologação, mesmo com o
microcódigo atualizado.

---

# PARTE V — Memória, swap e diagnóstico do hardware

## 15. Conferir RAM e swap

```bash
free -h
```

```bash
swapon --show
```

O diagnóstico do PowerEdge 2950 encontrou aproximadamente **4 GiB de RAM**.

### Se `swapon --show` não retornar nenhuma linha

Crie um swapfile de 4 GiB:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

Torne persistente:

```bash
grep -q '^/swapfile ' /etc/fstab || \
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Confira:

```bash
free -h
```

```bash
swapon --show
```

Swap reduz risco de OOM durante builds, mas não substitui expansão de RAM.

---

## 16. Checkpoint de hardware e armazenamento

```bash
df -hT
```

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

```bash
sudo pvs
sudo vgs
sudo lvs
```

Rede:

```bash
ip -br addr
```

```bash
ip route
```

Hardware:

```bash
sudo ipmitool chassis status
```

```bash
sudo ipmitool sdr type Temperature
```

```bash
sudo ipmitool sdr type Fan
```

Falhas do sistema:

```bash
systemctl --failed
```

### Pare se encontrar

- `/srv` não montado;
- RAID/armazenamento com erro;
- temperatura anormal;
- falha grave no systemd;
- `enp5s0` sem conectividade;
- ausência inesperada de espaço em disco.

---

# PARTE VI — Segurança básica do host

## 17. Instalar UFW e Fail2ban

```bash
sudo apt install -y ufw fail2ban
```

```bash
sudo systemctl enable --now fail2ban
```

```bash
sudo fail2ban-client status
```

---

## 18. Proteger SSH com Fail2ban

```bash
sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'EOF'
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
EOF
```

```bash
sudo systemctl restart fail2ban
```

```bash
sudo fail2ban-client status sshd
```

---

## 19. Configurar UFW sem perder o acesso

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw show added
sudo ufw enable
sudo ufw status verbose
```

Não adicione aqui regras para `8000`, `8080` ou `8025`. O controle das portas
Docker será feito pela cadeia `DOCKER-USER`.

---

# PARTE VII — Estrutura compartilhada do servidor multipropósito

## 20. Criar grupos

```bash
sudo groupadd -f projetos
sudo groupadd -f alunos
sudo usermod -aG projetos sperotto
```

---

## 21. Criar a estrutura `/srv`

```bash
sudo mkdir -p \
  /srv/projects \
  /srv/data \
  /srv/docker \
  /srv/backups \
  /srv/backups/diario-de-dor \
  /srv/alunos \
  /srv/cluster \
  /srv/config
```

Funções:

```text
/srv/projects   repositórios Git
/srv/data       dados persistentes externos aos volumes Docker
/srv/docker     data-root compartilhado do Docker
/srv/backups    backups separados por projeto
/srv/alunos     áreas dos estudantes
/srv/cluster    configuração operacional futura do cluster
/srv/config     inventários administrativos do host
```

Proprietários:

```bash
sudo chown sperotto:projetos /srv/projects
sudo chown sperotto:projetos /srv/data
sudo chown root:root /srv/docker
sudo chown sperotto:projetos /srv/backups
sudo chown root:alunos /srv/alunos
sudo chown sperotto:projetos /srv/cluster
sudo chown root:projetos /srv/config
```

Permissões:

```bash
sudo chmod 2775 /srv/projects
sudo chmod 2770 /srv/data
sudo chmod 0755 /srv/docker
sudo chmod 2770 /srv/backups
sudo chmod 2770 /srv/alunos
sudo chmod 2770 /srv/cluster
sudo chmod 2770 /srv/config
```

---

## 22. Criar registro central de portas

```bash
sudo tee /srv/config/PORTS.md >/dev/null <<'EOF'
# Registro de portas — stargate-master

Atualizar este arquivo ANTES de publicar uma nova porta Docker.

| Porta | Protocolo | Serviço | Projeto | Exposição |
|---:|---|---|---|---|
| 22 | TCP | SSH | host | host |
| 8000 | TCP | API | Diário de Dor | LAN UNEMAT |
| 8080 | TCP | Web | Diário de Dor | LAN UNEMAT |
| 8025 | TCP | MailHog | Diário de Dor | LAN UNEMAT / somente testes |
| 80 | TCP | reservado para proxy reverso compartilhado futuro | infraestrutura | ainda não usar |
| 443 | TCP | reservado para proxy reverso compartilhado futuro | infraestrutura | ainda não usar |

Nunca publicar diretamente, salvo decisão técnica explícita:
5432 PostgreSQL
6379 Redis
3306 MySQL/MariaDB
27017 MongoDB
EOF
```

```bash
cat /srv/config/PORTS.md
```

Para qualquer novo sistema: registrar porta, revisar firewall, revisar Compose e
só então subir containers.

---

# PARTE VIII — Contas dos alunos

## 23. Criar usuários

```bash
ALUNOS="aluno01 aluno02 aluno03"
```

```bash
for u in $ALUNOS; do
  sudo adduser "$u"
  sudo usermod -aG alunos "$u"
  sudo chage -d 0 "$u"
done
```

**Não adicionar alunos a** `sudo`, `docker`, `root`, `adm` ou `projetos` sem
necessidade explicitamente aprovada.

---

## 24. Criar área individual

```bash
for u in $ALUNOS; do
  sudo mkdir -p "/srv/alunos/$u"
  sudo chown "$u:alunos" "/srv/alunos/$u"
  sudo chmod 2750 "/srv/alunos/$u"
done
```

```bash
id aluno01
```

```bash
getent group sudo
getent group docker
```

---

# PARTE IX — Instalar Docker Engine oficial

## 25. Remover pacotes conflitantes

```bash
sudo apt remove -y \
  docker.io \
  docker-compose \
  docker-compose-v2 \
  docker-doc \
  docker-buildx \
  podman-docker \
  containerd \
  runc 2>/dev/null || true
```

---

## 26. Adicionar chave do Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
```

```bash
sudo curl -fsSL \
  https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
```

```bash
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

---

## 27. Adicionar repositório oficial

```bash
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

```bash
cat /etc/apt/sources.list.d/docker.sources
```

No Ubuntu 26.04, espere:

```text
Suites: resolute
```

```bash
sudo apt update
```

```bash
apt-cache policy docker-ce
```

Se `Candidate:` aparecer como `(none)`, pare. Não force suite de outra versão.

---

## 28. Instalar Docker

```bash
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

```bash
sudo systemctl status docker --no-pager
```

---

# PARTE X — Armazenamento compartilhado do Docker em `/srv`

## 29. Parar Docker

```bash
sudo systemctl stop docker.service docker.socket
```

---

## 30. Criar data-root

```bash
sudo mkdir -p /srv/docker/data-root
sudo chown -R root:root /srv/docker
```

---

## 31. Configurar daemon

```bash
if [ -f /etc/docker/daemon.json ]; then
  sudo cp /etc/docker/daemon.json \
    "/etc/docker/daemon.json.bak.$(date +%Y%m%d-%H%M%S)"
fi
```

```bash
sudo mkdir -p /etc/docker
```

```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "data-root": "/srv/docker/data-root",
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
```

```bash
jq . /etc/docker/daemon.json
```

---

## 32. Garantir `/srv` antes do Docker

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
```

```bash
sudo tee /etc/systemd/system/docker.service.d/storage.conf >/dev/null <<'EOF'
[Unit]
RequiresMountsFor=/srv/docker
After=local-fs.target
EOF
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now docker
```

---

## 33. Validar Docker

```bash
sudo docker info --format '{{.DockerRootDir}}'
```

Esperado:

```text
/srv/docker/data-root
```

```bash
sudo docker run --rm hello-world
```

```bash
sudo docker version
sudo docker compose version
```

---

## 34. Autorizar Docker ao administrador

```bash
sudo usermod -aG docker sperotto
```

```bash
getent group docker
```

Saia e entre novamente:

```bash
exit
```

Depois:

```bash
docker version
docker compose version
```


# PARTE XI — Firewall Docker preparado para vários sistemas

## 35. Conceito

O guia anterior protegia somente as portas atuais do Diário de Dor. Como o
servidor receberá outros sistemas, a política agora usa:

1. um arquivo central de configuração;
2. uma cadeia própria `STARGATE-DOCKER-LAN`;
3. a cadeia `DOCKER-USER`;
4. uma allowlist de portas publicadas;
5. bloqueio por padrão das demais novas conexões Docker que entrarem por
   `enp5s0`.

A futura rede do cluster em `enp9s0` não é modificada.

---

## 36. Criar configuração central do firewall Docker

```bash
sudo mkdir -p /etc/stargate
```

```bash
sudo tee /etc/stargate/docker-firewall.conf >/dev/null <<'EOF'
LAN_IF="enp5s0"
LAN_NET="10.28.15.0/24"

# Portas ORIGINAIS publicadas no host e permitidas para a LAN.
# Antes de acrescentar outra porta, registre-a em /srv/config/PORTS.md.
ALLOWED_TCP_PORTS="8000 8080 8025"
EOF
```

```bash
sudo chmod 640 /etc/stargate/docker-firewall.conf
```

```bash
sudo cat /etc/stargate/docker-firewall.conf
```

> Se a TI informar outra rede institucional, altere `LAN_NET`.

---

## 37. Criar script idempotente

```bash
sudo tee /usr/local/sbin/stargate-docker-firewall.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/stargate/docker-firewall.conf"

if [[ ! -r "$CONFIG" ]]; then
  echo "ERRO: $CONFIG ausente ou ilegível." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG"

: "${LAN_IF:?LAN_IF não definido}"
: "${LAN_NET:?LAN_NET não definido}"
: "${ALLOWED_TCP_PORTS:?ALLOWED_TCP_PORTS não definido}"

iptables -N DOCKER-USER 2>/dev/null || true
iptables -N STARGATE-DOCKER-LAN 2>/dev/null || true

# A cadeia própria é reconstruída a cada execução.
iptables -F STARGATE-DOCKER-LAN

# Garante que o tráfego institucional destinado aos containers passe primeiro
# pela política do Stargate.
iptables -C DOCKER-USER -i "$LAN_IF" -j STARGATE-DOCKER-LAN 2>/dev/null || \
  iptables -I DOCKER-USER 1 -i "$LAN_IF" -j STARGATE-DOCKER-LAN

iptables -A STARGATE-DOCKER-LAN \
  -m conntrack --ctstate RELATED,ESTABLISHED \
  -j ACCEPT

for port in $ALLOWED_TCP_PORTS; do
  iptables -A STARGATE-DOCKER-LAN \
    -s "$LAN_NET" \
    -p tcp \
    -m conntrack --ctstate NEW --ctorigdstport "$port" \
    -j ACCEPT
done

# Bloqueia qualquer outra nova conexão encaminhada pelo Docker via enp5s0.
iptables -A STARGATE-DOCKER-LAN \
  -m conntrack --ctstate NEW \
  -j DROP

iptables -A STARGATE-DOCKER-LAN -j RETURN
EOF
```

```bash
sudo chmod 750 /usr/local/sbin/stargate-docker-firewall.sh
```

### Explicação

O Docker executa DNAT antes da cadeia `DOCKER-USER`. Por isso o script usa
`--ctorigdstport`: ele compara a porta originalmente publicada no host, como
`8080`, mesmo quando internamente o container recebe na porta `80`.

---

## 38. Criar serviço systemd

```bash
sudo tee /etc/systemd/system/stargate-docker-firewall.service >/dev/null <<'EOF'
[Unit]
Description=Firewall de containers do stargate-master
Requires=docker.service
After=docker.service
PartOf=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/stargate-docker-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
```

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl enable --now stargate-docker-firewall.service
```

```bash
sudo systemctl status stargate-docker-firewall.service --no-pager
```

Confira:

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

```bash
sudo iptables -L STARGATE-DOCKER-LAN -n -v --line-numbers
```

---

## 39. Como adicionar porta de outro sistema

Primeiro:

```bash
sudo nano /srv/config/PORTS.md
```

Depois:

```bash
sudo nano /etc/stargate/docker-firewall.conf
```

Exemplo:

```text
ALLOWED_TCP_PORTS="8000 8080 8025 8180"
```

Reaplique:

```bash
sudo systemctl restart stargate-docker-firewall.service
```

Confira:

```bash
sudo iptables -L STARGATE-DOCKER-LAN -n -v --line-numbers
```

Não abra grandes faixas de portas apenas por conveniência.

---

# PARTE XII — GitHub para vários repositórios

## 40. Estratégia

Não usar senha, token pessoal ou chave SSH pessoal do professor no servidor.

Para cada repositório privado, usar **Deploy Key própria e somente leitura**.

O `cluster-stargate` é público e pode ser clonado via HTTPS.

---

## 41. Preparar diretório SSH

Como `sperotto`, sem `sudo`:

```bash
mkdir -p ~/.ssh/deploy
chmod 700 ~/.ssh
chmod 700 ~/.ssh/deploy
```

---

## 42. Criar Deploy Key do Diário de Dor

```bash
ssh-keygen \
  -t ed25519 \
  -N '' \
  -f ~/.ssh/deploy/id_ed25519_diario_de_dor \
  -C "stargate-master diario-de-dor read-only"
```

```bash
chmod 600 ~/.ssh/deploy/id_ed25519_diario_de_dor
chmod 644 ~/.ssh/deploy/id_ed25519_diario_de_dor.pub
```

Exiba **somente a chave pública**:

```bash
cat ~/.ssh/deploy/id_ed25519_diario_de_dor.pub
```

Cadastre no GitHub:

```text
Lucas-Sperotto/diario-de-dor-platform
Settings
Deploy keys
Add deploy key
```

Não habilite escrita.

---

## 43. Criar alias SSH

```bash
touch ~/.ssh/config
chmod 600 ~/.ssh/config
```

Adicione:

```bash
cat >> ~/.ssh/config <<'EOF'

Host github-diario
    HostName github.com
    User git
    IdentityFile ~/.ssh/deploy/id_ed25519_diario_de_dor
    IdentitiesOnly yes
EOF
```

Teste:

```bash
ssh -T git@github-diario
```

Para outros repositórios privados, crie outra chave e outro alias, por exemplo:

```text
github-entomo
github-correcao-pdf
```

---

# PARTE XIII — Clonar documentos do Stargate

## 44. Clonar `cluster-stargate`

```bash
cd /srv/projects
```

```bash
git clone https://github.com/Lucas-Sperotto/cluster-stargate.git
```

```bash
cd /srv/projects/cluster-stargate
```

```bash
git status
```

```bash
ls -lh
```

O relatório mais completo usado nesta revisão é:

```text
relatorio_stargate_master_poweredge2950_v3.md
```

Leia quando necessário:

```bash
less relatorio_stargate_master_poweredge2950_v3.md
```

Esses relatórios são referência histórica. O estado pós-formatação deve sempre
ser confirmado por comandos executados no servidor.

---

# PARTE XIV — Clonar a versão validada do Diário de Dor

## 45. Ir para projetos

```bash
cd /srv/projects
```

---

## 46. Clonar

```bash
git clone \
  git@github-diario:Lucas-Sperotto/diario-de-dor-platform.git
```

```bash
cd /srv/projects/diario-de-dor-platform
```

Confira:

```bash
git remote -v
```

```bash
git branch --show-current
```

Esperado:

```text
main
```

Atualize sem permitir merge automático:

```bash
git pull --ff-only
```

---

## 47. Confirmar SHA validado

```bash
EXPECTED_SHA="d27826040891c28f1ce66d13f5d7050738084538"
```

```bash
ACTUAL_SHA=$(git rev-parse HEAD)
```

```bash
echo "$ACTUAL_SHA"
```

```bash
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ATENÇÃO: main mudou desde a revisão deste guia."
  echo "Esperado: $EXPECTED_SHA"
  echo "Atual:    $ACTUAL_SHA"
  echo "PARE e revise a nova versão antes de instalar."
  exit 1
fi
```

---

## 48. Confirmar que o overlay de intranet é versionado

```bash
git ls-files compose.intranet.yaml
```

Esperado:

```text
compose.intranet.yaml
```

### Não faça mais

```text
cat > compose.intranet.yaml ...
echo "compose.intranet.yaml" >> .git/info/exclude
```

O arquivo agora faz parte oficialmente do repositório.

Confira:

```bash
git status --short
```

A árvore rastreada deve estar limpa.

---

# PARTE XV — Gate manual que substitui temporariamente o Actions

## 49. Executar gate sem E2E

```bash
cd /srv/projects/diario-de-dor-platform
```

```bash
./scripts/manual_quality_gate.sh
```

Esse comando valida:

- Compose;
- Ruff/formatter;
- Mypy;
- Pytest;
- dependências Python;
- PostgreSQL/Redis descartáveis;
- Alembic;
- `alembic check`;
- npm;
- testes mobile;
- export web;
- guarda anti-loopback;
- audit de dependências críticas;
- build API/Web.

Resultado esperado:

```text
[manual-gate] APROVADO
```

Se falhar, pare no primeiro erro real.

---

## 50. Instalar Chromium do Playwright

O gate sem E2E já executou `npm ci`. Agora:

```bash
cd /srv/projects/diario-de-dor-platform/apps/mobile
```

```bash
npx playwright install --with-deps chromium
```

Volte:

```bash
cd /srv/projects/diario-de-dor-platform
```

---

## 51. Executar gate completo

Para reduzir paralelismo:

```bash
CI=1 RUN_E2E=1 ./scripts/manual_quality_gate.sh
```

Resultado esperado:

```text
[manual-gate] APROVADO
```

Referência da auditoria independente anterior:

```text
pytest backend: 186 passed
vitest mobile:  32 passed
Playwright:      7/7 passed
Alembic head:    20260910_0013
alembic check:   limpo
```

---

# PARTE XVI — Preparar o ambiente real da intranet

## 52. Descobrir o IPv4 institucional

```bash
SERVER_IP=$(ip -4 -o addr show enp5s0 | awk '{print $4}' | cut -d/ -f1)
```

```bash
echo "$SERVER_IP"
```

Confirme:

```bash
ip -4 addr show enp5s0
```

```bash
ip route
```

Não continue se o endereço estiver vazio, for loopback ou pertencer a
Docker/VPN. Passe o IP explicitamente ao script seguinte.

---

## 53. Gerar `.env` pelo script do repositório

```bash
./scripts/prepare_intranet_env.sh "$SERVER_IP"
```

O script:

- valida IPv4;
- gera segredos;
- não mostra segredos;
- cria `.env` restrito;
- define CORS;
- define frontend/API;
- valida o Compose.

### Mudança importante

Não gere manualmente `API_SECRET_KEY`, `POSTGRES_PASSWORD`, `DATABASE_URL`,
`REDIS_PASSWORD` ou `compose.intranet.yaml`.

No perfil atual, Redis permanece somente na rede Docker e não usa `requirepass`
na homologação sintética.

---

## 54. Conferir apenas valores não secretos

```bash
grep -E \
'^(COMPOSE_PROJECT_NAME|ENVIRONMENT|SERVER_IP|APP_VERSION|BUILD_ID|API_CORS_ORIGINS|APP_BASE_URL|EXPO_PUBLIC_API_BASE_URL)=' \
.env
```

Esperado:

```text
COMPOSE_PROJECT_NAME=diario_de_dor_intranet
ENVIRONMENT=development
SERVER_IP=IP_REAL
API_CORS_ORIGINS=http://IP_REAL:8080
APP_BASE_URL=http://IP_REAL:8080
EXPO_PUBLIC_API_BASE_URL=http://IP_REAL:8000
```

Permissão:

```bash
stat -c '%a %U:%G %n' .env
```

O modo deve ser `600`.

Confira ignore:

```bash
git check-ignore -v .env
```

Nunca execute:

```text
git add .env
```

---

# PARTE XVII — Validar e construir a implantação

## 55. Validar Compose

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  config --quiet
```

Serviços:

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  config --services
```

Esperado:

```text
postgres
redis
api
mailhog
web
```

---

## 56. Conferir conflitos de portas

```bash
cat /srv/config/PORTS.md
```

```bash
sudo ss -lntp | grep -E ':(8000|8080|8025)\b' || true
```

Se já existir outro serviço nessas portas, identifique-o antes de continuar.

---

## 57. Baixar imagens externas

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  pull postgres redis mailhog
```

---

## 58. Construir API

```bash
COMPOSE_PARALLEL_LIMIT=1 docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  build api
```

Monitore, se necessário:

```bash
free -h
```

---

## 59. Construir frontend

```bash
COMPOSE_PARALLEL_LIMIT=1 docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  build web
```

Se o build acusar `api.localhost`/loopback, não desative a proteção. Corrija a
URL da API.

---

# PARTE XVIII — Subir o Diário de Dor

## 60. Iniciar

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  up -d
```

---

## 61. Conferir containers

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  ps
```

Se houver reinício contínuo:

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  logs --tail=200
```


# PARTE XIX — Aplicar e validar migrations

## 62. Aplicar migrations

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  exec -T api alembic upgrade head
```

---

## 63. Confirmar head

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  exec -T api alembic current
```

Esperado:

```text
20260910_0013 (head)
```

---

## 64. Confirmar ausência de drift

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  exec -T api alembic check
```

Esperado:

```text
No new upgrade operations detected.
```

---

# PARTE XX — Testar no endereço correto

## 65. Saúde da API

O perfil de intranet publica a API em `${SERVER_IP}:8000`. Portanto use:

```bash
curl -fsS "http://${SERVER_IP}:8000/health"
```

```bash
echo
```

Readiness:

```bash
curl -fsS "http://${SERVER_IP}:8000/health/ready"
```

```bash
echo
```

Esperado:

```json
{"status":"ready","postgres":"ok","redis":"ok"}
```

---

## 66. Frontend

```bash
curl -fsSI "http://${SERVER_IP}:8080/" | head
```

Espere HTTP `200`.

---

## 67. MailHog

```bash
curl -fsSI "http://${SERVER_IP}:8025/" | head
```

---

## 68. Confirmar que bancos não foram publicados

```bash
sudo ss -lntp | grep -E ':(5432|6379)\b' && \
  echo "ATENÇÃO: banco/cache publicado no host — investigar." || \
  echo "OK: 5432 e 6379 não aparecem como listeners do host."
```

Veja tudo:

```bash
sudo ss -lntup
```

Portas Docker:

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

---

# PARTE XXI — Testar pela rede da UNEMAT

## 69. Mostrar endereços

```bash
echo "Diário de Dor: http://${SERVER_IP}:8080"
```

```bash
echo "API:            http://${SERVER_IP}:8000"
```

```bash
echo "MailHog:        http://${SERVER_IP}:8025"
```

Em outro computador da rede:

```text
http://IP_DO_SERVIDOR:8000/health
http://IP_DO_SERVIDOR:8000/health/ready
http://IP_DO_SERVIDOR:8080
```

MailHog, apenas para teste/administração:

```text
http://IP_DO_SERVIDOR:8025
```

---

## 70. Testar firewall Docker

No servidor:

```bash
sudo iptables -L STARGATE-DOCKER-LAN -n -v --line-numbers
```

Os contadores devem aumentar conforme acessos são feitos.

---

# PARTE XXII — Cadastro e login sintéticos

## 71. Testar pela interface

1. abra `http://IP_DO_SERVIDOR:8080`;
2. crie conta com e-mail sintético;
3. abra MailHog;
4. confirme o e-mail;
5. faça login com **e-mail + senha**;
6. confirme o dashboard;
7. registre apenas dados fictícios.

O login atual usa **e-mail**, não CPF.

Se a interface abrir e o login falhar, não mude código de imediato. Registre:

- status da chamada `/api/v1/auth/login`;
- corpo de erro da API sem senha;
- logs da API;
- resultado de `/health/ready`;
- URL efetivamente chamada pelo navegador.

---

## 72. Seed sintético opcional

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  exec -T api python -m app.cli demo-seed --prefix aula
```

Não salve credenciais geradas no GitHub.

---

# PARTE XXIII — Logs e recursos

## 73. Logs gerais

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  logs --tail=100
```

---

## 74. Logs da API ao vivo

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  logs -f api
```

`Ctrl+C` apenas encerra a visualização.

---

## 75. Recursos

```bash
docker stats
```

```bash
free -h
```

```bash
vmstat 1
```

```bash
iostat -xz 1
```

Com 4 GiB de RAM:

- evitar builds simultâneos;
- executar inicialmente um stack pesado por vez;
- não rodar OCR e Playwright junto com outras cargas pesadas;
- observar swap;
- medir antes de definir limites permanentes.

---

# PARTE XXIV — Reboot e persistência

## 76. Reiniciar

Depois da validação:

```bash
sudo reboot
```

Após voltar:

```bash
docker ps
```

Recupere o IP:

```bash
SERVER_IP=$(ip -4 -o addr show enp5s0 | awk '{print $4}' | cut -d/ -f1)
```

Teste:

```bash
curl -fsS "http://${SERVER_IP}:8000/health/ready"
```

```bash
curl -fsSI "http://${SERVER_IP}:8080/" | head
```

Firewall:

```bash
systemctl status stargate-docker-firewall.service --no-pager
```

### DHCP

Se o IP mudar, o frontend antigo continuará contendo o endereço anterior.

Nesse caso:

1. confirmar o novo IP;
2. recriar/ajustar `.env`;
3. reconstruir `web`;
4. recriar a pilha.

Solicite à TI uma **reserva DHCP** para uso contínuo.

---

# PARTE XXV — Backup inicial

## 77. Criar dump

```bash
cd /srv/projects/diario-de-dor-platform
```

```bash
BACKUP_FILE="/srv/backups/diario-de-dor/diario_$(date +%Y%m%d_%H%M%S).dump"
```

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  exec -T postgres \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$BACKUP_FILE"
```

```bash
ls -lh "$BACKUP_FILE"
```

```bash
pg_restore -l "$BACKUP_FILE" | head
```

`/srv/backups` fica no mesmo servidor. **RAID não é backup.** Para dados
importantes, mantenha cópia em outro equipamento/storage autorizado.

---

# PARTE XXVI — Operação normal

## 78. Parar sem apagar dados

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  stop
```

---

## 79. Iniciar

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  start
```

---

## 80. Remover containers sem remover volumes

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  down
```

Não use na implantação:

```text
docker compose down -v
```

---

# PARTE XXVII — Atualizar o Diário de Dor no futuro

## 81. Antes da atualização

1. backup;
2. `git status`;
3. revisar SHA;
4. gate manual ou CI quando voltar;
5. revisar migrations.

---

## 82. Estado Git

```bash
cd /srv/projects/diario-de-dor-platform
```

```bash
git status
git branch --show-current
git rev-parse HEAD
```

---

## 83. Buscar nova versão

```bash
git fetch --prune
```

Veja o que mudará:

```bash
git log --oneline HEAD..origin/main
```

Depois de revisão:

```bash
git pull --ff-only
```

---

## 84. Atualizar BUILD_ID

```bash
NEW_BUILD_ID=$(git rev-parse --short HEAD)
```

```bash
sed -i "s/^BUILD_ID=.*/BUILD_ID=${NEW_BUILD_ID}/" .env
```

---

## 85. Validar atualização

```bash
./scripts/manual_quality_gate.sh
```

Se quiser gate completo:

```bash
CI=1 RUN_E2E=1 ./scripts/manual_quality_gate.sh
```

---

## 86. Reconstruir

```bash
COMPOSE_PARALLEL_LIMIT=1 docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  build api
```

```bash
COMPOSE_PARALLEL_LIMIT=1 docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  build web
```

---

## 87. Aplicar migrations

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  up -d postgres redis mailhog
```

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  run --rm api alembic upgrade head
```

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  run --rm api alembic check
```

---

## 88. Subir nova versão

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  up -d --remove-orphans
```

```bash
curl -fsS "http://${SERVER_IP}:8000/health/ready"
```

```bash
curl -fsSI "http://${SERVER_IP}:8080/" | head
```

---

# PARTE XXVIII — Regras para outros sistemas no `stargate-master`

## 89. Isolamento por projeto

Exemplo:

```text
/srv/projects/diario-de-dor-platform
/srv/projects/entomo-digitizer
/srv/projects/correcao-pdf

/srv/backups/diario-de-dor
/srv/backups/entomo-digitizer
/srv/backups/correcao-pdf
```

Cada Compose deve possuir nome único.

Nunca reutilize `diario_de_dor_intranet` em outro sistema.

---

## 90. Não compartilhar bancos por conveniência

Cada sistema deve preferencialmente possuir:

- banco próprio;
- usuário de banco próprio;
- volume próprio;
- rede própria;
- secrets próprios;
- migrations próprias.

Compartilhamento só com arquitetura explícita.

---

## 91. Portas

Antes de subir outro projeto:

```bash
cat /srv/config/PORTS.md
```

```bash
sudo ss -lntup
```

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Atualize o inventário:

```bash
sudo nano /srv/config/PORTS.md
```

Se houver nova porta Docker para a LAN:

```bash
sudo nano /etc/stargate/docker-firewall.conf
```

Depois:

```bash
sudo systemctl restart stargate-docker-firewall.service
```

---

## 92. Bancos devem ficar internos

Ao revisar outro Compose, procure especialmente:

```yaml
postgres:
  ports:
```

```yaml
redis:
  ports:
```

```yaml
mysql:
  ports:
```

Isso deve ser exceção e ter justificativa.

---

## 93. Proxy reverso futuro

Arquitetura futura:

```text
Rede institucional
       |
       v
  80 / 443
       |
proxy reverso compartilhado
       |
       +--> Diário de Dor
       +--> Entomo Digitizer
       +--> correção de PDF
       +--> outros
```

Enquanto o proxy não existir, use portas registradas e o firewall central.

Não suba dois proxies disputando 80/443.

---

## 94. Recursos antes de outro stack

```bash
free -h
```

```bash
docker stats --no-stream
```

```bash
df -hT
```

```bash
docker system df
```

Com a RAM atual, considere parar stacks não necessários antes de OCR, builds ou
testes E2E.

---

# PARTE XXIX — Comandos rápidos

## Estado do Diário de Dor

```bash
cd /srv/projects/diario-de-dor-platform
```

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  ps
```

## Saúde

```bash
SERVER_IP=$(ip -4 -o addr show enp5s0 | awk '{print $4}' | cut -d/ -f1)
```

```bash
curl -fsS "http://${SERVER_IP}:8000/health"
```

```bash
curl -fsS "http://${SERVER_IP}:8000/health/ready"
```

## Logs

```bash
docker compose \
  --env-file .env \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  logs --tail=100 api
```

## Recursos

```bash
docker stats
```

## Espaço

```bash
df -hT
```

```bash
docker system df
```

## Portas

```bash
sudo ss -lntup
```

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

## Firewall

```bash
sudo iptables -L STARGATE-DOCKER-LAN -n -v --line-numbers
```

---

# PARTE XXX — Comandos proibidos sem autorização

Não executar:

```text
sudo rm -rf ...
docker system prune -a --volumes
docker compose down -v
docker volume rm ...
lvremove
vgremove
pvremove
fdisk /dev/sda
wipefs
mkfs
iptables -F
iptables -F DOCKER-USER
ufw reset
Ctrl+R -> Delete Virtual Disk
Ctrl+R -> Initialize
Ctrl+R -> Clear Configuration
Force WB with no battery
```

Também não:

- editar `/etc/docker/daemon.json` sem revisão;
- alterar allowlist de portas sem atualizar o inventário;
- compartilhar `.env`;
- copiar chaves privadas;
- usar token/login GitHub pessoal do professor;
- adicionar alunos a `sudo` ou `docker`;
- usar dados reais de pacientes;
- publicar PostgreSQL/Redis;
- alterar RAID;
- alterar Netplan remotamente sem backup;
- executar `git reset --hard` no repositório de deploy;
- executar `git clean -fd` sem revisar exatamente o que será removido.

---

# PARTE XXXI — Checklist final

```text
[ ] Ubuntu atualizado
[ ] microcódigo Intel instalado/verificado
[ ] /srv montado corretamente
[ ] RAM e swap conferidos
[ ] enp5s0 funcionando
[ ] enp9s0 reservada/opcional
[ ] systemctl --failed sem falhas graves
[ ] SSH acessível
[ ] UFW ativo
[ ] Fail2ban ativo
[ ] Docker instalado do repositório oficial
[ ] Docker Root Dir = /srv/docker/data-root
[ ] sperotto no grupo docker
[ ] alunos fora de sudo/docker
[ ] /srv/config/PORTS.md criado
[ ] firewall STARGATE-DOCKER-LAN ativo
[ ] cluster-stargate clonado
[ ] Deploy Key do Diário de Dor é somente leitura
[ ] Diário de Dor em main@d27826040891c28f1ce66d13f5d7050738084538
[ ] compose.intranet.yaml é o arquivo versionado
[ ] manual_quality_gate.sh passou
[ ] Chromium Playwright instalado
[ ] CI=1 RUN_E2E=1 manual_quality_gate.sh passou, se executado
[ ] .env foi gerado por prepare_intranet_env.sh
[ ] .env tem chmod 600
[ ] .env é ignorado pelo Git
[ ] SERVER_IP corresponde à enp5s0
[ ] API_CORS_ORIGINS = http://SERVER_IP:8080
[ ] APP_BASE_URL = http://SERVER_IP:8080
[ ] EXPO_PUBLIC_API_BASE_URL = http://SERVER_IP:8000
[ ] PostgreSQL não publica 5432
[ ] Redis não publica 6379
[ ] API responde em /health
[ ] API responde em /health/ready
[ ] Web responde em SERVER_IP:8080
[ ] MailHog responde em SERVER_IP:8025
[ ] Alembic current = 20260910_0013 (head)
[ ] alembic check = limpo
[ ] cadastro sintético testado
[ ] confirmação por MailHog testada
[ ] login por e-mail testado
[ ] firewall Docker testado
[ ] reboot testado
[ ] backup PostgreSQL criado
[ ] nenhuma credencial foi incluída em Git
```

---

# PARTE XXXII — Próximas evoluções

1. solicitar à TI reserva DHCP para `enp5s0`;
2. aumentar RAM, preferencialmente para pelo menos 8 GiB;
3. inventariar os demais sistemas antes de publicá-los;
4. criar Deploy Key independente para cada repositório privado;
5. medir consumo de cada stack;
6. implantar proxy reverso compartilhado quando houver vários sistemas;
7. reservar 80/443 para esse proxy;
8. definir a rede privada do cluster em `enp9s0`;
9. manter bancos internos às redes Docker;
10. estabelecer backup fora do RAID;
11. migrar para staging/HTTPS somente com conectividade e política aprovadas.

---

# Referências consideradas nesta revisão

```text
Lucas-Sperotto/cluster-stargate
  relatorio_stargate_master_poweredge2950_v3.md

Lucas-Sperotto/diario-de-dor-platform
  main@d27826040891c28f1ce66d13f5d7050738084538
  compose.intranet.yaml
  scripts/prepare_intranet_env.sh
  scripts/manual_quality_gate.sh
  .github/workflows/ci.yml
```

O diagnóstico do `cluster-stargate` é referência histórica. O estado real
pós-formatação deve ser confirmado no servidor.

---

# Resultado esperado

```text
stargate-master
│
├── Ubuntu Server 26.04 LTS
├── sperotto — administrador
├── alunos — sem sudo/docker
├── SSH + UFW + Fail2ban
├── swap de segurança, se necessário
├── /srv
│   ├── projects/
│   │   ├── cluster-stargate/
│   │   ├── diario-de-dor-platform/
│   │   └── outros projetos
│   ├── data/
│   ├── backups/
│   ├── docker/data-root/
│   ├── alunos/
│   ├── cluster/
│   └── config/PORTS.md
│
├── firewall Docker central
│   └── STARGATE-DOCKER-LAN
│
└── Docker
    ├── diario_de_dor_intranet
    │   ├── postgres     interno
    │   ├── redis        interno
    │   ├── api          SERVER_IP:8000
    │   ├── web          SERVER_IP:8080
    │   └── mailhog      SERVER_IP:8025
    │
    └── futuros projetos
        └── nomes/portas/volumes separados
```

O servidor fica preparado para homologação privada do Diário de Dor com dados
sintéticos **e para receber outros sistemas sem transformar a configuração do
Diário de Dor na configuração global de todo o host**.

# PARTE XXXIII — Acesso SSH externo ao `stargate-master`

> **ETAPA ADMINISTRATIVA — NÃO EXECUTAR PELOS ALUNOS SEM AUTORIZAÇÃO**
>
> Esta parte deve ser executada pelo professor/administrador depois que o
> servidor estiver estável na rede interna.
>
> Existem duas situações diferentes:
>
> 1. **acesso SSH direto pela Internet** — depende da TI disponibilizar IP
>    público/roteamento/NAT e liberar a porta;
> 2. **acesso SSH privado por túnel/VPN de saída** — funciona mesmo quando a
>    universidade não aceita conexões entrantes, desde que a política
>    institucional permita o serviço e a rede aceite as conexões de saída.
>
> Um domínio DNS **não torna sozinho um IP privado acessível pela Internet**.

---

## 95. Confirmar que o SSH local está saudável antes de qualquer acesso externo

No servidor:

```bash
systemctl status ssh --no-pager
```

Confira a porta:

```bash
sudo ss -lntp | grep ':22 '
```

Valide a configuração:

```bash
sudo sshd -t
```

### Explicação

- o primeiro comando verifica o serviço OpenSSH;
- `ss` mostra sockets/listeners;
- `sshd -t` valida a sintaxe da configuração sem reiniciar o serviço.

Se `sshd -t` imprimir erro, **não reinicie o SSH** até corrigir.

---

## 96. Criar uma chave de administração no computador do professor

A chave deve ser criada **no computador de onde o professor acessará o
servidor**, e não no servidor.

Em Linux/macOS:

```bash
ssh-keygen -t ed25519 -a 64 -C "administracao-stargate"
```

Em Windows PowerShell, com OpenSSH instalado, o mesmo comando funciona:

```powershell
ssh-keygen -t ed25519 -a 64 -C "administracao-stargate"
```

Use uma passphrase forte.

### Arquivos criados normalmente

```text
id_ed25519       chave PRIVADA — não compartilhar
id_ed25519.pub   chave PÚBLICA — pode ser instalada no servidor
```

---

## 97. Instalar a chave pública no usuário `sperotto`

Enquanto ainda estiver na rede local, em Linux/macOS pode-se usar:

```bash
ssh-copy-id sperotto@IP_DO_SERVIDOR
```

Se `ssh-copy-id` não estiver disponível, copie **somente** o conteúdo de
`id_ed25519.pub` e, no servidor, faça:

```bash
mkdir -p ~/.ssh
```

```bash
chmod 700 ~/.ssh
```

```bash
nano ~/.ssh/authorized_keys
```

Cole a chave pública inteira em uma única linha, salve e depois:

```bash
chmod 600 ~/.ssh/authorized_keys
```

### Teste obrigatório

Abra uma **segunda sessão** e confirme que a chave funciona antes de desligar
autenticação por senha:

```bash
ssh sperotto@IP_DO_SERVIDOR
```

---

## 98. Endurecer o SSH depois que a chave estiver comprovadamente funcionando

Crie um arquivo separado para não editar diretamente o arquivo principal:

```bash
sudo tee /etc/ssh/sshd_config.d/90-stargate-hardening.conf >/dev/null <<'EOF'
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 4
AllowUsers sperotto
EOF
```

Valide:

```bash
sudo sshd -t
```

Se não houver erro:

```bash
sudo systemctl reload ssh
```

### Por que `reload` e não `restart`

`reload` pede ao serviço que releia a configuração, reduzindo a chance de
interromper sessões existentes.

### Teste novamente

Mantenha a sessão atual aberta e abra outra:

```bash
ssh sperotto@IP_DO_SERVIDOR
```

Somente depois desse teste considere a autenticação por senha desativada com
segurança.

---

## 99. Opção A — SSH direto pela Internet, apenas se a TI fornecer conectividade

Para SSH direto funcionar, a universidade precisa fornecer um caminho de
entrada, por exemplo:

```text
Internet
  |
IP público / firewall institucional
  |
NAT ou roteamento autorizado
  |
stargate-master:22
```

### O que deve ser solicitado à TI

- IP público ou mecanismo institucional equivalente;
- regra de firewall/NAT;
- porta externa autorizada;
- origem permitida, preferencialmente apenas os IPs administrativos;
- confirmação de que a política permite administração remota.

### Se o professor possuir IP público fixo em casa

Depois que a TI liberar o caminho, limite o UFW ao IP administrativo:

```bash
sudo ufw allow from IP_PUBLICO_DA_CASA to any port 22 proto tcp
```

Confira:

```bash
sudo ufw status numbered
```

### Muito importante

Se a TI **não** criar o roteamento/NAT, nenhum comando executado no
`stargate-master` consegue transformar `10.28.15.x` em servidor SSH público.

Criar um DNS como:

```text
ssh.exemplo.com -> 10.28.15.x
```

também não resolve, porque endereços privados não são roteáveis pela Internet.

---

## 100. Opção B recomendada quando não há porta de entrada — Tailscale

Quando a rede institucional não permite entrada direta, uma alternativa é
Tailscale, que cria uma rede privada criptografada usando conexões iniciadas
pelos próprios dispositivos.

**Use somente se esse tipo de túnel for permitido pela política da instituição.**

### Instalar no Ubuntu Server

O instalador oficial atual pode ser executado com:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Depois:

```bash
sudo tailscale up --ssh
```

O comando mostrará uma URL de autenticação. Abra-a no navegador do professor e
associe o servidor à conta/tailnet adequada.

### Conferir

```bash
tailscale status
```

```bash
tailscale ip -4
```

O segundo comando normalmente exibirá um endereço privado Tailscale.

### Do computador externo

Instale Tailscale também no computador do professor e autentique na mesma
tailnet.

Então use:

```bash
tailscale ssh sperotto@stargate-master
```

ou, se preferir usar o cliente OpenSSH normal e as políticas permitirem:

```bash
ssh sperotto@IP_TAILSCALE_DO_SERVIDOR
```

### Por que esta opção é adequada ao cenário atual

Ela não exige publicar a porta 22 do PowerEdge diretamente na Internet. O
controle de acesso deve ser feito pelas políticas da tailnet e apenas a conta
do administrador deve receber permissão SSH.

---

# PARTE XXXIV — Associar o Diário de Dor a um domínio registrado

> **ETAPA ADMINISTRATIVA E OPCIONAL**
>
> O ambiente atual continua sendo de **homologação com dados sintéticos**.
> Colocar o sistema em um domínio não transforma esta versão em produção
> autorizada e não autoriza dados reais.

---

## 101. Entender o problema de rede antes de configurar DNS

O Diário de Dor está atualmente em:

```text
Web: http://IP_PRIVADO:8080
API: http://IP_PRIVADO:8000
```

Um registro DNS comum só funciona publicamente quando existe um IP público
roteável até o servidor.

Como a rede da universidade atualmente não fornece acesso entrante, há duas
estratégias:

```text
A) TI libera IP público + 80/443 -> proxy reverso -> aplicações

B) servidor abre um túnel de SAÍDA -> provedor do túnel -> domínio público
```

Para o cenário atual, a opção B é mais compatível tecnicamente.

---

## 102. Opção recomendada para testes externos — Cloudflare Tunnel

O Cloudflare Tunnel permite que `cloudflared`, executando no servidor, faça uma
conexão **de saída** para a Cloudflare. Assim não é necessário publicar um IP
público diretamente no PowerEdge.

Pré-requisitos:

- domínio registrado;
- domínio adicionado à conta Cloudflare;
- nameservers do domínio apontados para a Cloudflare;
- autorização institucional para esse acesso externo;
- apenas dados sintéticos nesta etapa.

### Hostnames sugeridos

Substitua `seudominio.com.br` pelo domínio real:

```text
dor.seudominio.com.br
api.dor.seudominio.com.br
```

**Não publique MailHog (`8025`) na Internet.**

---

## 103. Criar o Tunnel no painel Cloudflare

No painel Cloudflare:

```text
Networking
Tunnels
Create a tunnel
```

Use um nome como:

```text
stargate-diario-de-dor
```

Escolha Linux como sistema operacional.

O painel fornecerá um comando contendo um token, parecido conceitualmente com:

```bash
sudo cloudflared service install TOKEN_FORNECIDO_PELO_CLOUDFLARE
```

### Segurança

O token do Tunnel é um segredo.

- não coloque no Git;
- não envie em grupos de alunos;
- não copie para este guia;
- execute-o somente no servidor.

Depois confira:

```bash
systemctl status cloudflared --no-pager
```

---

## 104. Criar os dois hostnames públicos no Tunnel

No painel do Tunnel, adicione uma aplicação publicada para o frontend:

```text
Hostname:
dor.seudominio.com.br

Service:
http://IP_REAL_DO_SERVIDOR:8080
```

Adicione outra para a API:

```text
Hostname:
api.dor.seudominio.com.br

Service:
http://IP_REAL_DO_SERVIDOR:8000
```

### Por que são dois hostnames

O navegador precisa carregar a interface web e também chamar a API. A versão
web do Expo incorpora a URL da API no bundle durante o build.

---

## 105. Criar um arquivo de ambiente específico para acesso externo

Não destrua o `.env` da intranet. Faça uma cópia administrativa:

```bash
cd /srv/projects/diario-de-dor-platform
```

```bash
cp .env .env.external
```

```bash
chmod 600 .env.external
```

Edite:

```bash
nano .env.external
```

Altere **somente os valores não secretos relacionados às URLs**.

Exemplo:

```dotenv
APP_DOMAIN=dor.seudominio.com.br
API_DOMAIN=api.dor.seudominio.com.br
APP_BASE_URL=https://dor.seudominio.com.br
API_CORS_ORIGINS=http://IP_REAL_DO_SERVIDOR:8080,https://dor.seudominio.com.br
EXPO_PUBLIC_API_BASE_URL=https://api.dor.seudominio.com.br
```

### Por que manter também a origem interna no CORS

Isso permite que o frontend continue sendo testado pela LAN enquanto a origem
externa também é aceita.

### Proteja o arquivo

Confira:

```bash
stat -c '%a %U:%G %n' .env.external
```

Deve aparecer modo `600`.

Confira se não será versionado:

```bash
git check-ignore -v .env.external
```

Se não estiver ignorado, **não faça `git add`**. Adicione o nome a
`.git/info/exclude` localmente:

```bash
echo ".env.external" >> .git/info/exclude
```

---

## 106. Reconstruir o frontend para usar a API pública

A URL da API é incorporada durante o build, portanto trocar apenas o DNS não é
suficiente.

Execute:

```bash
COMPOSE_PARALLEL_LIMIT=1 docker compose \
  --env-file .env.external \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  build web
```

Depois atualize a pilha usando o arquivo externo:

```bash
docker compose \
  --env-file .env.external \
  -f docker-compose.yml \
  -f compose.intranet.yaml \
  up -d --remove-orphans
```

### Valide localmente primeiro

```bash
SERVER_IP=$(grep '^SERVER_IP=' .env.external | cut -d= -f2-)
```

```bash
curl -fsS "http://${SERVER_IP}:8000/health/ready"
```

---

## 107. Testar os domínios

De um computador fora da rede institucional, por exemplo usando 4G/5G:

```bash
curl -I https://dor.seudominio.com.br
```

```bash
curl -fsS https://api.dor.seudominio.com.br/health
```

```bash
curl -fsS https://api.dor.seudominio.com.br/health/ready
```

Depois abra:

```text
https://dor.seudominio.com.br
```

Crie somente uma conta sintética e teste login.

---

## 108. Verificar o serviço do Tunnel

No servidor:

```bash
systemctl status cloudflared --no-pager
```

Logs recentes:

```bash
journalctl -u cloudflared -n 100 --no-pager
```

Acompanhar ao vivo:

```bash
journalctl -u cloudflared -f
```

`Ctrl+C` encerra somente a visualização.

---

## 109. O que não deve ser exposto externamente

Nunca crie hostname público para:

```text
PostgreSQL :5432
Redis      :6379
MailHog    :8025
Docker API
DRAC/IPMI
```

O domínio público deve expor apenas o que for necessário à aplicação.

---

## 110. Se a TI futuramente liberar 80/443

Nesse cenário, o desenho preferido para vários sistemas será:

```text
Internet
   |
80 / 443
   |
proxy reverso compartilhado
   |
   +--> Diário de Dor
   +--> Entomo Digitizer
   +--> demais sistemas
```

Então:

- DNS `A`/`AAAA` apontará para o endereço público institucional;
- TLS/HTTPS será terminado no proxy reverso compartilhado;
- cada aplicação continuará em sua rede Docker;
- apenas o proxy ocupará 80/443;
- Cloudflare Tunnel poderá ser removido se deixar de ser necessário.

Não configure um proxy público até a TI fornecer o caminho de entrada e a
política institucional correspondente.

---

# PARTE XXXV — Checklist de acesso externo

```text
[ ] SSH local por chave foi testado antes de desativar senha
[ ] root login por SSH está desativado
[ ] somente sperotto está autorizado para administração SSH
[ ] nenhum aluno possui chave de administração
[ ] foi definido se o acesso externo será direto ou por Tailscale
[ ] nenhuma porta SSH pública foi criada sem autorização da TI
[ ] domínio está registrado e sob controle administrativo
[ ] Cloudflare Tunnel foi autorizado pela instituição, se utilizado
[ ] dor.DOMINIO aponta para o frontend
[ ] api.dor.DOMINIO aponta para a API
[ ] frontend foi reconstruído com a URL pública da API
[ ] CORS inclui somente as origens necessárias
[ ] MailHog não está exposto externamente
[ ] PostgreSQL não está exposto externamente
[ ] Redis não está exposto externamente
[ ] DRAC/IPMI não está exposto externamente
[ ] teste externo foi feito com dados exclusivamente sintéticos
```
