# Relatório técnico e plano de reinstalação — `stargate-master`

**Equipamento:** Dell PowerEdge 2950  
**Hostname a preservar:** `stargate-master`  
**Administrador principal:** `sperotto`  
**Sistema atual:** Ubuntu Server 24.04.3 LTS (Noble), kernel 6.8.0-139-generic  
**Data do levantamento:** 09/09/2026  

---

## 1. Objetivo

Preparar o Dell PowerEdge 2950 para funcionar como servidor acadêmico/laboratorial multipropósito, mantendo:

- o hostname `stargate-master`;
- o usuário `sperotto` como administrador;
- usuários individuais para os alunos, sem privilégios administrativos por padrão;
- Docker e Docker Compose para isolamento dos projetos;
- hospedagem do **Diário de Dor**;
- hospedagem do backend/PWA do **Entomo Digitizer**;
- hospedagem do projeto de correção de PDFs de aula;
- possibilidade de adicionar outros projetos;
- função de controlador/mestre do cluster;
- SSH para administração;
- estrutura organizada de dados, projetos e backups.

A proposta evita instalar diretamente no host bancos, frameworks e dependências específicas de cada projeto. Sempre que possível, esses componentes devem ficar dentro de containers.

---

# 2. Inventário atual

## 2.1 Servidor

| Item | Resultado |
|---|---|
| Fabricante | Dell Inc. |
| Modelo | PowerEdge 2950 |
| Hostname | `stargate-master` |
| BIOS | 1.3.7 |
| Data da BIOS | 26/03/2007 |
| Arquitetura | x86-64 |
| Sistema | Ubuntu 24.04.3 LTS |
| Kernel | 6.8.0-139-generic |

### Observação sobre a BIOS

A BIOS instalada (`1.3.7`, de 2007) é muito antiga. A Dell publicou posteriormente a BIOS **2.7.0** para o PowerEdge 2950, classificada como atualização urgente, incluindo atualizações de microcódigo para processadores Xeon da série 5100.

**Não atualizar a BIOS automaticamente antes de verificar:**

1. revisão exata do PowerEdge 2950;
2. estado das fontes;
3. existência de nobreak/UPS;
4. instruções oficiais de atualização;
5. necessidade de atualização intermediária;
6. integridade do DRAC;
7. backup das configurações.

Uma falha de energia durante atualização de BIOS pode inutilizar a placa.

---

## 2.2 Processadores

Foram encontrados:

- **2 sockets físicos**;
- **Intel Xeon 5160 @ 3.00 GHz**;
- 2 núcleos por processador;
- 4 núcleos totais;
- 1 thread por núcleo;
- 4 CPUs lógicas;
- cache L2 total: 8 MiB.

Resumo:

```text
2 × Intel Xeon 5160
2 cores por CPU
4 cores totais
3,00 GHz
```

### Virtualização

O comando:

```bash
egrep -o 'vmx|svm' /proc/cpuinfo | sort -u
```

não retornou `vmx`.

Isso significa que o Linux atualmente **não está enxergando Intel VT-x**.

Isso não impede Docker, porque containers não precisam de virtualização de hardware. Entretanto, impede ou limita KVM/VMs.

Antes de concluir que o processador não oferece o recurso, verificar na BIOS se existe a opção:

```text
Virtualization Technology
Intel Virtualization Technology
VT
VT-x
```

e se ela está habilitada.

---

## 2.3 Vulnerabilidades reportadas pela CPU

O `lscpu` indicou, entre outras informações:

- MDS: vulnerável / microcódigo não disponível no estado atual;
- Spec Store Bypass: vulnerável;
- Meltdown: mitigado por PTI;
- Spectre v1: mitigado;
- Spectre v2: mitigado parcialmente por mecanismos do kernel.

Como o equipamento é antigo, deve ser tratado como **servidor de laboratório/homologação**, não como plataforma ideal para exposição direta à Internet ou processamento de informações altamente sensíveis.

Recomenda-se verificar BIOS e microcódigo Intel antes da entrada em operação.

---

# 3. Memória RAM

## Configuração atual

```text
Total detectado: aproximadamente 4 GiB
Tipo: DDR2 FB-DIMM ECC
Velocidade: 667 MT/s
Slots: 8
Máximo reportado pelo SMBIOS: 32 GB
```

Slots atuais:

| Slot | Capacidade |
|---|---:|
| DIMM1 | 1 GB |
| DIMM2 | 1 GB |
| DIMM3 | 1 GB |
| DIMM4 | 1 GB |
| DIMM5 | vazio |
| DIMM6 | vazio |
| DIMM7 | vazio |
| DIMM8 | vazio |

A memória utiliza ECC e está instalada em pares.

## Avaliação

**4 GiB é o principal gargalo atual.**

É suficiente para:

- Ubuntu Server sem interface gráfica;
- SSH;
- Docker;
- controlador simples do cluster;
- um ou poucos serviços leves;
- testes de um projeto por vez.

É pouco para manter simultaneamente:

- vários PostgreSQL;
- Redis;
- APIs Python;
- Django;
- FastAPI;
- OCR/Tesseract;
- múltiplos frontends;
- builds;
- processos do cluster.

### Recomendação

Prioridade de upgrade:

1. **mínimo desejável: 8 GB**;
2. **bom para esse laboratório: 12–16 GB**;
3. **ideal dentro das possibilidades dessa máquina: 16–32 GB**, se módulos compatíveis forem encontrados a custo razoável.

Usar FB-DIMM ECC compatíveis e respeitar a instalação em pares exigida pelo servidor.

---

# 4. Armazenamento e RAID

## 4.1 Controlador

Foi detectado:

```text
Dell PowerEdge Expandable RAID Controller 5
PERC 5/i
driver Linux: megaraid_sas
```

O kernel reconheceu o controlador normalmente.

Há também:

```text
Adaptec ASC-39320A U320
```

com dois canais SCSI.

---

## 4.2 Discos físicos detectados pelo kernel

O log mostra três discos:

```text
SEAGATE ST3300555SS
SEAGATE ST3300555SS
SEAGATE ST3300555SS
```

Cada modelo é apresentado pelo controlador como disco físico SAS.

O sistema operacional recebe do PERC um único disco lógico:

```text
/dev/sda
aproximadamente 557,8 GiB
modelo: PERC 5/i
```

Três discos de aproximadamente 300 GB resultando em volume lógico de aproximadamente 600 GB decimais são **forte indício de RAID 5**.

Isso ainda deve ser confirmado diretamente no PERC antes da formatação.

---

## 4.3 Particionamento atual

```text
/dev/sda        ~557,8 GiB
├── sda1        1 MiB      BIOS boot
├── sda2        2 GiB      ext4 /boot
└── sda3        ~555,7 GiB LVM
    └── ubuntu-vg/ubuntu-lv
                    100 GiB ext4 /
```

### Achado importante

Embora o volume RAID tenha aproximadamente **557,8 GiB**, o sistema de arquivos raiz atual possui apenas aproximadamente **100 GiB**.

Portanto, aparentemente há cerca de **455 GiB dentro do volume group ainda não alocados ao logical volume raiz**.

Confirmar com:

```bash
sudo pvs
sudo vgs
sudo lvs
```

Esse comportamento é comum em instalações guiadas com LVM.

Na reinstalação não devemos repetir esse desperdício sem intenção.

---

# 5. DRAC 5

O hardware apresentou:

```text
DRAC5 VIRTUAL MEDIA
Virtual CDROM
Virtual Floppy
```

Isso confirma que o servidor possui **DRAC 5 com mídia virtual** visível pelo sistema.

Portanto, além de pendrive, existe a possibilidade de reinstalação usando ISO montada pela interface de gerenciamento remoto do DRAC, caso a rede e as credenciais do DRAC estejam disponíveis.

Antes da formatação, coletar:

```bash
sudo ipmitool mc info
sudo ipmitool chassis status
sudo ipmitool lan print
```

Caso `lan print` não mostre o canal correto:

```bash
sudo ipmitool channel info 1
sudo ipmitool channel info 2
sudo ipmitool channel info 3
```

---

# 6. Temperatura e ventilação

Temperatura ambiente reportada:

```text
25 °C
```

Ventoinhas:

```text
FAN 1: 6375 RPM
FAN 2: 6300 RPM
FAN 3: 5775 RPM
FAN 4: 5850 RPM
```

Redundância:

```text
Fully Redundant
```

Não foram observados serviços `systemd` em estado `failed`.

Esse é um bom sinal inicial, mas não substitui inspeção de discos, fontes, bateria/cache do PERC e log de eventos do BMC.

---

# 7. Rede

Foram encontradas duas interfaces Broadcom NetXtreme II BCM5708 Gigabit Ethernet.

## Interface 1

```text
enp5s0
estado: UP
velocidade: 1000 Mb/s
duplex: Full
IP atual: 10.28.15.254/24
gateway: 10.28.15.1
```

## Interface 2

```text
enp9s0
estado: DOWN
```

A segunda interface pode ser utilizada futuramente para:

- rede privada do cluster;
- tráfego entre nós;
- separação entre rede institucional e rede do cluster;
- backup;
- administração.

Uma arquitetura interessante seria:

```text
enp5s0
    ↓
Rede institucional / acesso aos sistemas

enp9s0
    ↓
Rede privada do cluster
```

Isso será definido apenas depois de conhecer os demais nós.

---

# 8. Docker atual

Versões encontradas:

```text
Docker 29.8.0
Docker Compose 5.5.1
```

Containers encontrados:

```text
diario_de_dor_intranet-web-1
diario_de_dor_intranet-api-1
diario_de_dor_intranet-postgres-1
diario_de_dor_intranet-redis-1
diario_de_dor_intranet-mailhog-1
```

No momento do levantamento:

- web: ativo;
- API: ativa e saudável;
- MailHog: ativo;
- PostgreSQL: parado;
- Redis: parado.

Volumes:

```text
diario_de_dor_intranet_postgres_data
diario_de_dor_intranet_redis_data
```

Redes Docker:

```text
diario_de_dor_intranet_backend
diario_de_dor_intranet_default
```

Projeto Git encontrado:

```text
/home/sperotto/diario-de-dor-platform
```

---

# 9. Portas atualmente abertas

Portas TCP expostas:

| Porta | Uso observado |
|---:|---|
| 22 | SSH |
| 8000 | container Docker |
| 8080 | container Docker |
| 8025 | MailHog |

As portas 8000, 8080 e 8025 estão vinculadas a:

```text
0.0.0.0
::
```

ou seja, estão publicadas em todas as interfaces do host.

Ao mesmo tempo:

```text
UFW: inactive
```

## Risco

Esse desenho é aceitável apenas temporariamente em rede controlada.

No sistema definitivo:

- não publicar PostgreSQL e Redis na rede;
- não publicar MailHog fora do ambiente de teste;
- colocar aplicações atrás de proxy reverso;
- expor preferencialmente apenas 22, 80 e 443;
- limitar SSH à rede necessária;
- aplicar regras também considerando o comportamento do Docker com iptables.

**Importante:** portas publicadas pelo Docker podem contornar regras simples do UFW. A política final deve considerar a cadeia `DOCKER-USER`/iptables e não depender apenas do UFW.

---

# 10. Serviços instalados no host

Serviços relevantes ativos:

```text
containerd
docker
ssh
cron
rsyslog
systemd-networkd
systemd-resolved
systemd-timesyncd
unattended-upgrades
```

Não foram encontrados instalados diretamente:

```text
nginx
apache2
postgresql client
mysql client
pip3
node
```

Isso é coerente com a estratégia de manter dependências das aplicações dentro de containers.

Git está instalado:

```text
git 2.43.0
```

Python do sistema:

```text
Python 3.12.3
```

---

# 11. Arquitetura recomendada após reinstalação

```text
stargate-master
│
├── Ubuntu Server 24.04 LTS
│
├── SSH
├── Git
├── Docker Engine
├── Docker Compose
├── firewall
├── fail2ban
├── monitoramento
│
├── /srv/
│   ├── projects/
│   │   ├── diario-de-dor-platform/
│   │   ├── entomo-digitizer/
│   │   ├── correcao-pdf/
│   │   └── outros/
│   │
│   ├── data/
│   │   ├── diario-de-dor/
│   │   ├── entomo-digitizer/
│   │   └── correcao-pdf/
│   │
│   └── backups/
│
├── reverse proxy
│
└── cluster/
    ├── configuração do controlador
    ├── chaves
    ├── inventário dos nós
    └── scripts
```

---

# 12. Estratégia de contas

## Administrador

Usuário:

```text
sperotto
```

Deve pertencer a:

```text
sudo
docker
```

Observação: pertencer ao grupo `docker` equivale, na prática, a possuir privilégios muito altos no servidor. Portanto, somente administradores devem entrar nesse grupo.

## Alunos

Criar um usuário Linux por aluno.

Exemplo:

```text
aluno01
aluno02
aluno03
...
```

Todos devem pertencer ao grupo:

```text
alunos
```

Por padrão:

- sem `sudo`;
- sem grupo `docker`;
- sem acesso às credenciais GitHub do administrador;
- sem acesso aos `.env` dos projetos;
- sem acesso às chaves privadas;
- acesso apenas aos diretórios necessários.

---

# 13. Comandos que ainda faltam executar ANTES de formatar

## 13.1 Confirmar LVM

```bash
sudo pvs
sudo vgs
sudo lvs -a -o +devices
```

---

## 13.2 Confirmar RAID e saúde dos discos

```bash
sudo smartctl --scan-open
```

Tentar os três discos atrás do PERC:

```bash
for i in 0 1 2; do
    echo "================ DISCO $i ================"
    sudo smartctl -a -d megaraid,$i /dev/sda
done
```

Procurar principalmente:

- SMART Health Status;
- Predictive Failure;
- Reallocated sectors;
- erros de leitura;
- temperatura;
- power-on hours.

Também:

```bash
sudo lsscsi -g
```

Se `lsscsi` não existir:

```bash
sudo apt update
sudo apt install -y lsscsi
```

---

## 13.3 Log de eventos do servidor

```bash
sudo ipmitool sel elist
```

Resumo:

```bash
sudo ipmitool sel info
```

Não limpar o SEL antes de analisá-lo.

---

## 13.4 Estado do chassis e gerenciamento

```bash
sudo ipmitool chassis status
sudo ipmitool mc info
```

Fontes:

```bash
sudo ipmitool sdr type "Power Supply"
```

Voltagens:

```bash
sudo ipmitool sdr type voltage
```

---

## 13.5 Microcódigo do processador

```bash
grep -m1 microcode /proc/cpuinfo
```

```bash
sudo dmesg | grep -i microcode
```

```bash
apt-cache policy intel-microcode
```

---

## 13.6 Processadores completos

```bash
sudo dmidecode --type processor
```

---

## 13.7 Configuração das interfaces

```bash
sudo ethtool -i enp5s0
sudo ethtool -i enp9s0
```

```bash
resolvectl status
```

```bash
sudo cat /etc/netplan/*.yaml
```

O arquivo de Netplan é importante porque precisamos saber se `10.28.15.254` é configurado manualmente ou recebido por DHCP.

Atualmente a rota indica:

```text
proto dhcp
```

portanto o endereço está sendo recebido via DHCP.

Para um nó mestre de cluster é preferível:

1. reserva DHCP permanente pela TI; ou
2. IP estático oficialmente reservado.

Não configurar manualmente `10.28.15.254` sem confirmar que ele pode ser reservado.

---

## 13.8 Montagens

```bash
cat /etc/fstab
```

---

## 13.9 Uso de disco

```bash
sudo du -xh --max-depth=1 /home 2>/dev/null | sort -h
sudo du -xh --max-depth=1 /var/lib/docker 2>/dev/null | sort -h
sudo du -xh --max-depth=1 /srv 2>/dev/null | sort -h
```

---

## 13.10 Uso de RAM dos containers

```bash
docker stats --no-stream
```

---

## 13.11 Estado do projeto Diário de Dor

```bash
cd /home/sperotto/diario-de-dor-platform
git status
git branch --show-current
git remote -v
docker compose ps
docker compose config --services
```

Não enviar `.env` nem segredos.

---

## 13.12 Pacotes instalados manualmente

```bash
apt-mark showmanual | sort
```

Salvar:

```bash
apt-mark showmanual | sort > ~/pacotes-manuais.txt
```

Inventário completo:

```bash
dpkg-query -W -f='${binary:Package}\t${Version}\n' > ~/pacotes-instalados.tsv
```

---

## 13.13 Tarefas agendadas

```bash
crontab -l
```

```bash
sudo crontab -l
```

```bash
sudo ls -lah /etc/cron.d /etc/cron.daily /etc/cron.weekly
```

---

## 13.14 Serviços personalizados

```bash
sudo find /etc/systemd/system -maxdepth 2 -type f -print
```

---

## 13.15 Configuração Git do usuário

```bash
git config --global --list
```

Não publicar tokens.

---

# 14. Backup mínimo antes da formatação

Criar:

```bash
mkdir -p ~/pre-reinstall-backup
```

## Configuração do sistema

```bash
sudo cp -a /etc/netplan ~/pre-reinstall-backup/
sudo cp -a /etc/ssh ~/pre-reinstall-backup/
sudo cp -a /etc/docker ~/pre-reinstall-backup/ 2>/dev/null || true
sudo cp -a /etc/systemd/system ~/pre-reinstall-backup/
sudo cp -a /etc/fstab ~/pre-reinstall-backup/fstab
sudo cp -a /etc/hosts ~/pre-reinstall-backup/hosts
sudo cp -a /etc/hostname ~/pre-reinstall-backup/hostname
```

Depois devolver a propriedade desses arquivos ao usuário:

```bash
sudo chown -R sperotto:sperotto ~/pre-reinstall-backup
```

## Chaves SSH

Verificar:

```bash
ls -lah ~/.ssh
```

Se houver chaves usadas para GitHub ou administração, copiá-las para uma mídia externa segura.

**Nunca colocar chave privada em repositório Git.**

---

# 15. Backup do repositório antes da reinstalação

Verificar se tudo foi enviado ao GitHub:

```bash
cd ~/diario-de-dor-platform
git status
git log --oneline -10
git remote -v
```

Se houver alterações importantes ainda não versionadas, revisar antes de formatar.

Não executar `git push` automaticamente sem revisar o conteúdo e garantir que arquivos `.env`, chaves, senhas ou dados sensíveis não estejam sendo versionados.

---

# 16. Backup de volumes Docker

Se houver qualquer dado que deva ser preservado, os volumes Docker devem ser tratados antes da formatação.

Volumes atuais:

```text
diario_de_dor_intranet_postgres_data
diario_de_dor_intranet_redis_data
```

Como o objetivo atual é laboratório/homologação com dados sintéticos, decidir se esses dados precisam realmente ser preservados.

Para descobrir o conteúdo/uso:

```bash
docker volume inspect diario_de_dor_intranet_postgres_data
docker volume inspect diario_de_dor_intranet_redis_data
```

Não reutilizar volumes antigos no novo sistema sem necessidade.

---

# 17. Instalação limpa do Ubuntu

Imagem recomendada para esse equipamento:

```text
Ubuntu Server 24.04.4 LTS amd64
```

O PowerEdge está executando corretamente Ubuntu 24.04 em x86-64, portanto a reinstalação da série 24.04 LTS é coerente.

Durante a instalação:

```text
Hostname: stargate-master
Nome do usuário: sperotto
Instalar OpenSSH Server: SIM
Ubuntu Desktop/GUI: NÃO
```

## Armazenamento

O ponto mais importante é não deixar aproximadamente 455 GiB sem utilização por acidente.

Duas alternativas:

### Alternativa A — simples

Usar LVM e, após a instalação, aumentar `/` para todo o espaço disponível.

É a alternativa mais simples para o laboratório.

### Alternativa B — organizada

Separar volumes:

```text
/                sistema
/srv             projetos e dados
/var/lib/docker  Docker
```

Essa alternativa é melhor administrativamente, mas requer dimensionamento e manutenção mais cuidadosos.

Para a primeira reconstrução do laboratório, recomenda-se a **Alternativa A**, com organização lógica por diretórios dentro de `/srv`.

---

# 18. Pós-instalação — hostname

Confirmar:

```bash
hostnamectl
```

Definir explicitamente:

```bash
sudo hostnamectl set-hostname stargate-master
```

Garantir entrada local:

```bash
if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sudo sed -i 's/^127\.0\.1\.1.*/127.0.1.1 stargate-master/' /etc/hosts
else
    echo '127.0.1.1 stargate-master' | sudo tee -a /etc/hosts
fi
```

Validar:

```bash
hostname
hostnamectl
getent hosts stargate-master
```

---

# 19. Pós-instalação — usuário administrador `sperotto`

Durante a instalação, criar diretamente:

```text
sperotto
```

Depois:

```bash
sudo usermod -aG sudo sperotto
```

Verificar:

```bash
id sperotto
```

```bash
getent group sudo
```

Resultado desejado:

```text
sudo: ... sperotto
```

---

# 20. Atualização inicial

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y
sudo apt clean
```

Reiniciar:

```bash
sudo reboot
```

Depois:

```bash
hostnamectl
uname -a
```

---

# 21. Pacotes básicos

```bash
sudo apt update
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
    ethtool \
    smartmontools \
    ipmitool \
    lsscsi \
    lm-sensors \
    sysstat \
    openssh-server \
    ufw \
    fail2ban
```

Ativar SSH:

```bash
sudo systemctl enable --now ssh
```

Verificar:

```bash
sudo systemctl status ssh --no-pager
```

---

# 22. Microcódigo Intel

Instalar:

```bash
sudo apt update
sudo apt install -y intel-microcode
```

Reiniciar:

```bash
sudo reboot
```

Depois:

```bash
dmesg | grep -i microcode
grep -m1 microcode /proc/cpuinfo
```

A disponibilidade de correção para esse processador depende do microcódigo fornecido para a geração específica; por isso o resultado deve ser conferido.

---

# 23. LVM após reinstalação

Verificar:

```bash
sudo pvs
sudo vgs
sudo lvs
df -hT
```

Se o instalador voltar a criar um root de apenas 100 GiB e o restante estiver livre no mesmo VG, pode-se ampliar o root.

Primeiro conferir o caminho:

```bash
sudo lvs
```

Se for:

```text
/dev/ubuntu-vg/ubuntu-lv
```

expandir:

```bash
sudo lvextend -l +100%FREE -r /dev/ubuntu-vg/ubuntu-lv
```

Validar:

```bash
df -hT
sudo vgs
sudo lvs
```

**Só executar o `lvextend` depois de conferir que o espaço livre realmente pertence ao VG correto.**

---

# 24. Estrutura `/srv`

Criar:

```bash
sudo mkdir -p /srv/projects
sudo mkdir -p /srv/data
sudo mkdir -p /srv/backups
sudo mkdir -p /srv/cluster
```

Grupo administrativo dos projetos:

```bash
sudo groupadd -f projetos
```

Adicionar `sperotto`:

```bash
sudo usermod -aG projetos sperotto
```

Permissões:

```bash
sudo chown -R sperotto:projetos /srv/projects
sudo chown -R sperotto:projetos /srv/data
sudo chown -R sperotto:projetos /srv/backups
sudo chown -R sperotto:projetos /srv/cluster
```

```bash
sudo chmod 2775 /srv/projects
sudo chmod 2775 /srv/data
sudo chmod 2770 /srv/backups
sudo chmod 2775 /srv/cluster
```

O bit `2` em `2775` ativa `setgid`, fazendo novos arquivos herdarem o grupo do diretório.

---

# 25. Criar grupo dos alunos

```bash
sudo groupadd -f alunos
```

Verificar:

```bash
getent group alunos
```

---

# 26. Criar usuários dos alunos

## Método recomendado

Editar a lista abaixo com os nomes reais:

```bash
ALUNOS="aluno01 aluno02 aluno03 aluno04 aluno05"
```

Depois:

```bash
for u in $ALUNOS; do
    sudo adduser "$u"
    sudo usermod -aG alunos "$u"
    sudo chage -d 0 "$u"
done
```

O `adduser` solicitará a senha inicial de cada conta.

O comando:

```bash
sudo chage -d 0 usuario
```

obriga o aluno a alterar a senha no primeiro login.

## Conferência

```bash
getent group alunos
```

```bash
getent group sudo
```

Apenas administradores devem aparecer no grupo `sudo`.

---

# 27. Impedir privilégios indevidos

Não adicionar alunos aos grupos:

```text
sudo
docker
root
adm
```

O grupo `docker` permite controle quase equivalente a root.

Verificar um aluno:

```bash
id aluno01
```

Resultado desejado:

```text
grupos básicos + alunos
```

e **não**:

```text
sudo
docker
```

---

# 28. Diretório compartilhado para atividades

Criar:

```bash
sudo mkdir -p /srv/alunos
sudo chown root:alunos /srv/alunos
sudo chmod 2770 /srv/alunos
```

Criar diretório de cada aluno:

```bash
for u in $ALUNOS; do
    sudo mkdir -p "/srv/alunos/$u"
    sudo chown "$u:alunos" "/srv/alunos/$u"
    sudo chmod 2750 "/srv/alunos/$u"
done
```

Assim cada aluno pode trabalhar em seu diretório.

---

# 29. Docker Engine

Para a reconstrução, usar o repositório oficial do Docker para Ubuntu.

Remover pacotes conflitantes, se houver:

```bash
sudo apt remove -y docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc 2>/dev/null || true
```

Adicionar chave:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

Adicionar repositório:

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

Atualizar:

```bash
sudo apt update
```

Instalar:

```bash
sudo apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
```

Ativar:

```bash
sudo systemctl enable --now docker
```

Testar:

```bash
sudo docker run --rm hello-world
```

---

# 30. Autorizar `sperotto` a administrar Docker

```bash
sudo usermod -aG docker sperotto
```

Sair da sessão SSH e entrar novamente.

Depois:

```bash
docker version
docker compose version
```

Novamente: **não adicionar alunos ao grupo Docker por padrão.**

---

# 31. Firewall inicial

Antes de ativar o UFW em uma sessão SSH, permitir SSH:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
```

Se os serviços web forem publicados:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Ativar:

```bash
sudo ufw enable
```

Verificar:

```bash
sudo ufw status verbose
```

## Atenção ao Docker

Regras simples de UFW não são suficientes para controlar todas as portas publicadas pelo Docker.

No desenho definitivo:

- não usar `0.0.0.0:5432`;
- não usar `0.0.0.0:6379`;
- evitar expor portas internas dos containers;
- publicar somente o proxy reverso;
- revisar `iptables`/`DOCKER-USER`.

---

# 32. Fail2ban

Ativar:

```bash
sudo systemctl enable --now fail2ban
```

Verificar:

```bash
sudo fail2ban-client status
```

Inicialmente utilizar proteção de SSH.

---

# 33. Git no servidor

Configurar apenas no usuário `sperotto`:

```bash
git config --global user.name "Sperotto"
```

Configurar o e-mail correto do GitHub:

```bash
git config --global user.email "SEU_EMAIL_DO_GITHUB"
```

Verificar:

```bash
git config --global --list
```

Não compartilhar credenciais pessoais do GitHub com os alunos.

Para repositórios privados, preferir:

- chave SSH exclusiva do servidor vinculada à conta adequada; ou
- deploy keys específicas; ou
- mecanismo institucional de autenticação.

---

# 34. Chave SSH do servidor para GitHub

No usuário `sperotto`:

```bash
ssh-keygen -t ed25519 -C "stargate-master"
```

Exibir somente a chave pública:

```bash
cat ~/.ssh/id_ed25519.pub
```

Nunca compartilhar:

```text
~/.ssh/id_ed25519
```

A chave privada permanece no servidor.

---

# 35. Clonar projetos

Diretório:

```bash
cd /srv/projects
```

Depois de configurar autenticação GitHub:

```bash
git clone git@github.com:Lucas-Sperotto/diario-de-dor-platform.git
git clone git@github.com:Lucas-Sperotto/entomo-digitizer.git
```

O projeto de correção de PDFs deve ser adicionado quando for identificado o nome exato do repositório.

---

# 36. Diário de Dor

O projeto já foi estruturado para usar:

- FastAPI;
- PostgreSQL;
- Redis;
- frontend;
- Docker Compose;
- proxy reverso/Traefik nos ambientes previstos.

Não instalar PostgreSQL ou Redis diretamente no host sem necessidade.

Após clonar:

```bash
cd /srv/projects/diario-de-dor-platform
```

Ler primeiro:

```bash
less README.md
```

Depois verificar:

```bash
docker compose config
```

Não subir o ambiente antes de revisar:

- `.env`;
- limites de memória;
- portas publicadas;
- volumes;
- dados sintéticos;
- modo staging/intranet.

---

# 37. Entomo Digitizer

O projeto utiliza:

- Django;
- Django REST Framework;
- PostgreSQL;
- Tesseract/OCR;
- ReportLab;
- Docker Compose;
- cliente Android separado.

O servidor hospeda principalmente:

```text
backend
PWA
PostgreSQL
arquivos/imagens
OCR
exportações
```

O APK Android continua executando no smartphone.

Depois de clonar:

```bash
cd /srv/projects/entomo-digitizer
less README.md
docker compose config
```

Com apenas 4 GiB de RAM, evitar executar simultaneamente OCR pesado e todos os serviços dos demais projetos.

---

# 38. Projeto de correção de PDFs

Criar diretório:

```bash
mkdir -p /srv/projects/correcao-pdf
```

A estratégia definitiva deve ser decidida após localizar e revisar o repositório.

Idealmente:

```text
container próprio
fila própria
diretório próprio
limite de CPU
limite de RAM
```

Processamento de PDF e OCR pode ser pesado para os quatro cores Xeon atuais.

---

# 39. Limites de recursos

Com a RAM atual, containers devem receber limites de memória.

Exemplo conceitual:

```yaml
services:
  app:
    mem_limit: 512m
    cpus: 1.0
```

Os valores corretos devem ser medidos para cada projeto.

Não configurar limites arbitrários antes de testar.

Com 4 GiB, recomenda-se inicialmente executar **um stack de aplicação por vez**, além dos serviços essenciais do host.

---

# 40. Master/controlador do cluster

É possível manter o PowerEdge como controlador mesmo sendo antigo.

Funções adequadas:

- SSH/orquestração;
- inventário dos nós;
- compartilhamento de configurações;
- scheduler/control plane leve;
- coleta de logs;
- monitoramento;
- armazenamento de scripts;
- nó de entrada.

Evitar atribuir ao mestre, ao mesmo tempo:

- OCR pesado;
- builds grandes;
- treinamento de IA;
- cargas numéricas intensivas;
- múltiplos bancos sob carga.

Essas tarefas devem ser distribuídas aos nós.

---

# 41. Segunda interface para o cluster

A interface:

```text
enp9s0
```

está livre.

Pode posteriormente receber uma rede privada, por exemplo:

```text
stargate-master enp9s0
        │
        └── switch privado
             ├── node01
             ├── node02
             ├── node03
             └── ...
```

Não definir IPs até conhecer o hardware e endereçamento dos demais nós.

---

# 42. Monitoramento básico

Ativar `sysstat`:

```bash
sudo systemctl enable --now sysstat
```

Comandos úteis:

```bash
htop
free -h
df -hT
docker stats
iostat -xz 1
vmstat 1
```

Sensores:

```bash
sudo ipmitool sdr
```

---

# 43. Backups

Criar:

```bash
sudo mkdir -p /srv/backups/docker
sudo mkdir -p /srv/backups/databases
sudo mkdir -p /srv/backups/config
```

Os backups **não devem existir apenas no mesmo RAID do servidor**.

RAID não é backup.

Manter cópia em:

- outro servidor;
- NAS;
- HD externo;
- storage institucional;
- nuvem autorizada.

---

# 44. Prioridades de melhoria do hardware

## Prioridade 1 — RAM

Subir de 4 GiB para pelo menos 8–16 GiB.

## Prioridade 2 — saúde do RAID

Verificar:

- três discos;
- estado SMART;
- estado do virtual disk;
- bateria/cache do PERC;
- erros históricos.

## Prioridade 3 — BIOS/microcódigo

A BIOS atual é 1.3.7/2007. Existe firmware posterior da Dell para o PE2950.

Atualização deve ser feita em procedimento separado e controlado.

## Prioridade 4 — rede do cluster

Usar `enp9s0` para tráfego privado quando os nós estiverem definidos.

## Prioridade 5 — backup externo

Obrigatório antes de qualquer uso que contenha informações importantes.

---

# 45. Avaliação geral

## Pontos positivos

- Ubuntu 24.04 já funciona corretamente no hardware;
- duas interfaces Gigabit;
- RAID por hardware;
- três discos SAS detectados;
- ECC;
- duas CPUs físicas;
- DRAC 5;
- mídia virtual;
- Docker funcional;
- SSH funcional;
- temperatura ambiente adequada;
- fan redundancy OK;
- nenhum serviço systemd em falha;
- aproximadamente 558 GiB de volume lógico RAID.

## Limitações

- apenas 4 GiB de RAM;
- apenas 4 cores;
- CPU muito antiga;
- BIOS muito antiga;
- vulnerabilidades de CPU/microcódigo;
- discos SAS antigos;
- PERC 5/i antigo;
- sem VT-x visível atualmente;
- desempenho energético baixo comparado a servidores modernos.

---

# 46. Conclusão

O Dell PowerEdge 2950 é **viável para o laboratório proposto**, principalmente como:

```text
servidor de desenvolvimento
servidor de homologação
servidor de intranet
host Docker
servidor acadêmico
controlador/master do cluster
repositório de serviços auxiliares
```

Ele não é uma boa escolha para:

```text
produção crítica exposta diretamente à Internet
grandes bancos sob carga
IA pesada
OCR concorrente em grande escala
máquinas virtuais numerosas
dados sensíveis sem uma camada adicional de segurança
```

O desenho mais adequado é:

```text
Ubuntu Server 24.04 LTS
        ↓
stargate-master
        ↓
sperotto = administrador
        ↓
alunos = contas individuais sem sudo/docker
        ↓
Docker
        ↓
containers independentes por projeto
        ↓
proxy reverso
        ↓
rede privada do cluster em segunda interface
        ↓
backups externos
```

Antes da formatação, executar os diagnósticos restantes deste documento e preservar somente configurações e dados realmente necessários.

---

# 47. Referências técnicas verificadas

- Canonical — Ubuntu Server 24.04 LTS: arquitetura amd64 suportada e requisitos mínimos de instalação.
- Canonical — Ubuntu Server 24.04.4 LTS: imagem Server amd64.
- Docker — instalação oficial do Docker Engine no Ubuntu 24.04 LTS.
- Dell — PowerEdge PE2950 BIOS 2.7.0, publicada em 23/08/2012, incluindo atualização de microcódigo para processadores Xeon da série 5100.

---

# 48. Próxima coleta recomendada

Executar e guardar a saída:

```bash
sudo pvs
sudo vgs
sudo lvs -a -o +devices

sudo smartctl --scan-open
for i in 0 1 2; do
    echo "================ DISCO $i ================"
    sudo smartctl -a -d megaraid,$i /dev/sda
done

sudo ipmitool sel elist
sudo ipmitool sel info
sudo ipmitool chassis status
sudo ipmitool mc info
sudo ipmitool sdr type "Power Supply"

grep -m1 microcode /proc/cpuinfo
sudo dmesg | grep -i microcode
apt-cache policy intel-microcode

sudo dmidecode --type processor

sudo ethtool -i enp5s0
sudo ethtool -i enp9s0
resolvectl status
sudo cat /etc/netplan/*.yaml

cat /etc/fstab
docker stats --no-stream
```

Essa coleta fecha o inventário necessário para decidir a reinstalação, armazenamento, rede e configuração do cluster.
