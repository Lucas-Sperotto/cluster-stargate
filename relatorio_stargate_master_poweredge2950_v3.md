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
---

# ATUALIZAÇÃO DE DIAGNÓSTICO — 09/09/2026

Esta seção incorpora a segunda rodada de diagnóstico, realizada antes da reinstalação.

## A. LVM confirmado

Os comandos:

```bash
sudo pvs
sudo vgs
sudo lvs -a -o +devices
```

confirmaram:

```text
PV: /dev/sda3
VG: ubuntu-vg
Tamanho do VG: ~555,75 GiB
LV raiz: 100 GiB
Espaço livre no VG: ~455,75 GiB
```

Portanto, o sistema atual realmente utiliza apenas 100 GiB para `/`, embora aproximadamente 455,75 GiB permaneçam livres no volume group.

### Decisão para a reinstalação

Na instalação nova, não repetir automaticamente um LV raiz de apenas 100 GiB sem planejamento.

Para este servidor, a opção inicial recomendada continua sendo:

- LVM;
- raiz com espaço suficiente;
- organização por `/srv`;
- deixar espaço livre no VG apenas se houver uma razão deliberada.

---

# B. RAID e discos físicos

O `smartctl --scan-open` identificou três discos físicos atrás do PERC:

```text
megaraid,0
megaraid,1
megaraid,2
```

Todos são:

```text
SEAGATE ST3300555SS
300 GB
SAS
15.000 RPM
```

Isso confirma três discos físicos de 300 GB.

O volume lógico apresentado ao Linux tem aproximadamente 557,8 GiB. A combinação é consistente com RAID 5 de três discos, mas o nível RAID ainda deve ser confirmado pelo utilitário do controlador ou pela tela Ctrl-R do PERC durante o POST.

## Disco físico 0

```text
Serial: 3LM175EZ
Temperatura: 48 °C
Power-on time: 56.830 horas
SMART Health Status: OK
Grown defect list: 20
Erros de leitura não corrigidos: 18
Non-medium error count: 1445
```

### Avaliação

Este é o disco que mais preocupa.

Embora o SMART geral ainda reporte `OK`, existem:

- 20 elementos na grown defect list;
- 18 erros de leitura não corrigidos;
- 1.445 non-medium errors;
- mais de 56 mil horas de operação.

**Classificação interna recomendada: ATENÇÃO ALTA.**

Não considerar esse disco adequado para dados importantes sem backup externo.

Não iniciar substituição/rebuild antes de garantir backup dos dados necessários, pois a reconstrução de RAID 5 impõe leitura intensiva aos discos restantes.

---

## Disco físico 1

```text
Serial: 3LM15R1G
Temperatura: 49 °C
Power-on time: 56.797 horas
SMART Health Status: OK
Grown defect list: 0
Erros de leitura não corrigidos: 0
Non-medium error count: 19
```

### Avaliação

Estado substancialmente melhor que o disco 0, porém:

- idade operacional muito alta;
- temperatura de 49 °C merece acompanhamento;
- não deve ser considerado um disco novo/confiável apenas porque o SMART está `OK`.

**Classificação interna recomendada: ATENÇÃO MODERADA.**

---

## Disco físico 2

```text
Serial: 3LM16YBF
Temperatura: 31 °C
Power-on time: 56.867 horas
SMART Health Status: OK
Grown defect list: 0
Erros de leitura não corrigidos: 0
Non-medium error count: 10
```

### Avaliação

É o melhor dos três no levantamento atual, mas também possui mais de 56 mil horas de operação.

**Classificação interna recomendada: ATENÇÃO MODERADA pela idade.**

---

# C. Situação geral dos discos

Resumo:

| Disco | Serial | Temp. | Grown defects | Uncorrected read errors | Avaliação |
|---|---|---:|---:|---:|---|
| 0 | 3LM175EZ | 48 °C | 20 | 18 | Atenção alta |
| 1 | 3LM15R1G | 49 °C | 0 | 0 | Atenção moderada |
| 2 | 3LM16YBF | 31 °C | 0 | 0 | Atenção moderada |

### Recomendação

Antes de colocar o servidor em operação contínua:

1. fazer backup externo;
2. confirmar nível e estado atual do RAID;
3. identificar fisicamente qual baia corresponde ao serial `3LM175EZ`;
4. avaliar substituição planejada do disco 0;
5. considerar substituição progressiva de todo o conjunto, devido à idade;
6. nunca tratar RAID como backup.

---

# D. SEL/BMC — log de eventos

O SEL reportou:

```text
Entries: 512
Free Space: 0 bytes
Percent Used: 100%
Overflow: true
```

O histórico contém numerosos eventos antigos relacionados a:

- bateria ROMB/PERC `Low`;
- bateria ROMB/PERC `Failed`;
- falhas de drives/baias;
- perda de redundância de fontes;
- perda de AC em fonte;
- desligamentos e reinicializações.

O log atingiu a capacidade total em 30/09/2020:

```text
Event Logging Disabled SEL | Log full | Asserted
```

### Consequência

O SEL atual **não pode ser usado para afirmar que não houve falhas depois de 2020**.

O registro simplesmente ficou cheio e deixou de registrar novos eventos.

Além disso, `ipmitool sel info` mostrou um `Last Add Time` em 2040, inconsistente com a data real, sugerindo relógio BMC/SEL incorreto ou metadado antigo/corrompido.

### Antes de limpar o SEL

Salvar uma cópia:

```bash
sudo ipmitool sel elist > ~/stargate-sel-before-clear.txt
sudo ipmitool sel info > ~/stargate-sel-info-before-clear.txt
```

Verificar:

```bash
wc -l ~/stargate-sel-before-clear.txt
```

Depois de preservar o histórico, pode-se limpar o SEL para voltar a registrar novos eventos:

```bash
sudo ipmitool sel clear
```

**Atenção:** `sel clear` apaga o histórico armazenado no BMC. Executar somente depois de salvar a cópia.

Depois:

```bash
sudo ipmitool sel info
sudo ipmitool sel elist
```

---

# E. Fontes de alimentação — problema atual

O estado atual mostrou:

```text
Power Supply 1:
Presence detected
Failure detected
Power Supply AC lost

Power Supply 2:
Presence detected

PS Redundancy:
Redundancy Lost
```

O chassis também informa que o sistema está ligado e não há `Main Power Fault`, mas a redundância está perdida.

### Interpretação

O servidor está funcionando com alimentação suficiente para permanecer ligado, porém uma das fontes:

- pode estar sem cabo AC;
- pode estar ligada a tomada/régua sem energia;
- pode estar defeituosa;
- pode apresentar falha de sensor ou conexão.

### Verificação física obrigatória

Antes da reinstalação:

1. verificar os dois cabos de força;
2. verificar LEDs traseiros de ambas as fontes;
3. testar a tomada/régua de cada fonte;
4. preferencialmente conectar cada fonte a circuito/saída independente de UPS;
5. repetir:

```bash
sudo ipmitool sdr type "Power Supply"
```

Estado desejado:

```text
Presence detected
sem Failure detected
sem Power Supply AC lost
PS Redundancy: Fully Redundant
```

**Não fazer atualização de BIOS/firmware enquanto a redundância de alimentação estiver perdida.**

---

# F. Bateria ROMB/PERC

O histórico possui múltiplos registros de:

```text
Battery ROMB Battery | Low
Battery ROMB Battery | Failed
```

durante vários anos.

Como o SEL ficou cheio em 2020, ele não revela o estado atual da bateria.

Antes de confiar em cache de escrita do PERC, é necessário consultar o estado atual do BBU.

## Comandos de diagnóstico disponíveis agora

Primeiro listar os sensores relacionados:

```bash
sudo ipmitool sdr elist | grep -Ei 'battery|romb'
```

Também:

```bash
sudo ipmitool sdr | grep -Ei 'battery|romb'
```

Guardar a saída.

## Verificação pelo controlador

O PERC 5/i pertence à geração antiga de controladores que utiliza a ferramenta MegaCLI, não o PERCCLI moderno usado pelas gerações PERC 8+.

Se MegaCLI compatível for instalado de fonte confiável, os comandos de leitura relevantes são:

```bash
sudo MegaCli64 -AdpAllInfo -aALL
sudo MegaCli64 -LDInfo -Lall -aALL
sudo MegaCli64 -LdPdInfo -aALL
sudo MegaCli64 -AdpBbuCmd -GetBbuStatus -aALL
sudo MegaCli64 -AdpBbuCmd -GetBbuCapacityInfo -aALL
```

O nome do executável pode ser `MegaCli`, `MegaCli64` ou caminho equivalente conforme o pacote utilizado.

**Não instalar binários aleatórios da Internet.** Preferir fonte Dell/Broadcom/LSI confiável.

Como alternativa segura, conferir o PERC no boot usando:

```text
Ctrl-R
```

e anotar:

- RAID level;
- Virtual Disk State;
- Physical Disk State;
- BBU/Battery state;
- Write Policy;
- firmware do PERC.

---

# G. Microcódigo

O processador reportou:

```text
microcode atual: 0xd2
```

O kernel informa:

```text
Updated early from: 0xc6
Current revision: 0xd2
```

O pacote atual está instalado:

```text
intel-microcode 3.20260210.0ubuntu0.24.04.1
```

Portanto o Ubuntu está aplicando a atualização de microcódigo disponível para esse processador.

Apesar disso, o kernel ainda informa:

```text
MDS: Vulnerable: Clear CPU buffers attempted, no microcode
```

### Conclusão

Não há uma correção completa disponível no estado atual para todas as vulnerabilidades reportadas por essa geração de CPU.

Isso reforça a classificação do servidor como:

```text
laboratório
intranet
homologação
master/controlador acadêmico
```

e não como host ideal para produção pública com dados sensíveis.

---

# H. Rede confirmada

## Interface principal

```text
enp5s0
driver: bnx2
Broadcom BCM5708
1 Gbit/s Full Duplex
firmware: bc 2.9.1
DHCP: ativo
IP observado: 10.28.15.254/24
DNS: 1.1.1.3 e 10.28.15.1
domínio: aia.unemat
```

Netplan atual:

```yaml
network:
  version: 2
  ethernets:
    enp5s0:
      dhcp4: true
```

Isso confirma que `10.28.15.254` **não está configurado estaticamente no servidor**.

Para preservar esse IP após a reinstalação, solicitar reserva DHCP à TI ou confirmar a política da rede.

## Interface secundária

```text
enp9s0
driver: bnx2
firmware: bc 2.9.1
estado atual: DOWN
```

Continua sendo uma boa candidata à rede privada do cluster.

---

# I. Docker e memória

Com os containers ativos no momento da coleta:

```text
web:      ~11 MiB
API:      ~108 MiB
MailHog:  ~11 MiB
```

A API apresentou aproximadamente 20% de CPU no instante da coleta.

PostgreSQL e Redis estavam parados nessa medição, portanto esse consumo **não representa o stack completo**.

### Consequência

O Diário de Dor pode funcionar nesse hardware para homologação, mas o consumo deve ser medido com:

- PostgreSQL ativo;
- Redis ativo;
- API;
- web;
- MailHog somente quando necessário;
- carga de teste.

Com 4 GiB, stacks adicionais devem ser subidos de forma controlada.

---

# J. Situação atual — classificação por prioridade

## CRÍTICO antes de confiar o servidor a dados importantes

1. Backup externo.
2. Verificar fonte sem AC/falha.
3. Restaurar redundância de energia.
4. Confirmar estado atual da bateria do PERC.
5. Confirmar RAID no Ctrl-R/MegaCLI.
6. Planejar substituição do disco serial `3LM175EZ`.

## ALTA prioridade

7. Aumentar RAM para pelo menos 8–16 GiB.
8. Limpar o SEL **somente depois de salvar o log**, para voltar a registrar eventos.
9. Considerar atualização de BIOS/firmwares, mas somente depois de resolver alimentação e backup.
10. Implementar monitoramento de RAID, temperatura e SEL.

## MÉDIA prioridade

11. Configurar firewall.
12. Organizar `/srv`.
13. Configurar rede privada do cluster em `enp9s0`.
14. Solicitar IP reservado para `enp5s0`.
15. Implantar backups automáticos fora do RAID local.

---

# K. Minha recomendação antes de formatar

**Ainda é possível reinstalar o Ubuntu, mas eu não faria isso imediatamente.**

A sequência mais segura agora é:

```text
1. salvar SEL
2. verificar a fonte 1/cabo AC
3. recuperar redundância das fontes
4. verificar bateria PERC
5. confirmar RAID 5 / estado do virtual disk
6. fazer backup do que precisa ser preservado
7. identificar o disco físico 0
8. decidir se troca o disco antes ou depois da reinstalação
9. somente então formatar
```

A reinstalação do Ubuntu não corrigirá:

- desgaste dos discos;
- bateria do PERC;
- fonte sem redundância;
- BIOS/firmware antigos;
- limitações de RAM.

Esses itens pertencem à camada física e devem ser tratados separadamente.

---

# ATUALIZAÇÃO DE DIAGNÓSTICO — TELA AVANÇADA DO PERC 5/i

Foi registrada uma nova tela do utilitário **PERC 5/i Integrated BIOS Configuration Utility**, na seção de propriedades do **Virtual Disk 0**.

## 1. Configuração confirmada do Virtual Disk

A tela apresenta:

```text
RAID Level      : RAID-5
RAID Status     : Optimal
VD Size         : 557.750 GB
VD Name         : stargate-master
Operation       : No Operation
Progress        : N/A
```

Os três discos físicos associados ao Virtual Disk continuam sendo:

```text
01:00   285568 MB
01:01   285568 MB
01:02   285568 MB
```

Portanto, a configuração está confirmada como:

```text
3 × discos SAS de 300 GB
        ↓
      RAID 5
        ↓
Virtual Disk 0
557,750 GB
nome: stargate-master
estado: Optimal
```

---

## 2. Stripe Element Size

A tela informa:

```text
Stripe Element Size: 64 KB
```

Esse é o tamanho de stripe atualmente configurado no Virtual Disk.

### Interpretação

O valor de 64 KB é compatível com uma configuração genérica de RAID 5 para cargas mistas.

Como o array está funcional e será utilizado para:

- sistema operacional;
- Docker;
- bancos de dados de homologação;
- arquivos;
- projetos;
- serviços do cluster;

não existe motivo para recriar o RAID apenas para alterar o stripe size.

**Recomendação:** manter o RAID atual e o stripe de 64 KB.

---

## 3. Política de leitura

A tela informa:

```text
Read Policy: Adaptive Read Ahead
```

Isso significa que o controlador pode utilizar read-ahead de maneira adaptativa, dependendo do padrão de acesso observado.

### Recomendação

Manter a política atual.

Não há necessidade de alteração para a reinstalação do Ubuntu.

---

## 4. Política de escrita

A tela informa:

```text
Write Policy: Write Through
```

e mostra:

```text
[ ] Force WB with no battery
```

A opção de forçar **Write Back sem bateria** está desmarcada.

### Interpretação

O PERC está operando em **Write Through**, isto é, considera a escrita concluída somente quando ela chegou ao armazenamento físico, em vez de depender do cache protegido por bateria.

Isso é mais seguro na ausência de uma bateria BBU confiável, mas pode reduzir significativamente o desempenho de escrita.

A combinação:

```text
Write Policy: Write Through
Force WB with no battery: desmarcado
```

é coerente com:

- bateria BBU/PERC ausente;
- bateria com falha;
- bateria descarregada;
- bateria considerada não segura pelo controlador;
- política conservadora configurada manualmente.

O histórico antigo do SEL já registrou repetidamente:

```text
Battery ROMB Battery | Low
Battery ROMB Battery | Failed
```

portanto existe forte evidência histórica de problema no BBU do controlador.

---

## 5. NÃO ativar "Force WB with no battery"

**Não marcar:**

```text
Force WB with no battery
```

A opção força o controlador a utilizar cache de escrita em modo Write Back mesmo sem proteção adequada da bateria.

Em caso de:

- falta de energia;
- desligamento abrupto;
- falha de fonte;
- travamento;

dados que ainda estiverem apenas no cache do controlador podem ser perdidos.

Para este servidor, até que a bateria do PERC seja substituída/verificada, a política recomendada é:

```text
Write Through
```

e não Write Back forçado.

---

## 6. Consequência para desempenho

O modo Write Through pode produzir desempenho inferior principalmente em:

- PostgreSQL;
- muitas gravações pequenas;
- logs;
- Docker;
- criação/remoção frequente de arquivos;
- builds;
- escrita concorrente.

Isso não impede o uso do servidor como laboratório.

Entretanto, para melhorar desempenho no futuro, o caminho correto é:

```text
1. substituir/verificar a bateria BBU do PERC
2. confirmar BBU = Optimal
3. deixar o próprio controlador habilitar Write Back protegido
```

e não forçar Write Back sem proteção.

---

## 7. Nome do Virtual Disk

O Virtual Disk atual possui:

```text
VD Name: stargate-master
```

Esse nome existe dentro do controlador PERC e é independente do hostname Linux.

Na nova instalação também será usado:

```text
hostname Linux: stargate-master
```

Portanto haverá consistência nominal entre:

```text
PERC VD Name : stargate-master
Linux Hostname: stargate-master
```

Isso é conveniente para documentação e manutenção.

---

## 8. Decisão final sobre o RAID antes da reinstalação

Com as telas do PERC, fica confirmado:

```text
PERC 5/i                OK
Virtual Disk 0          OK
RAID Level              RAID 5
RAID Status             Optimal
Virtual Disk Size       557.750 GB
Virtual Disk Name       stargate-master
Physical Disks          3
Physical Disk State     Online
Stripe Element Size     64 KB
Read Policy             Adaptive Read Ahead
Write Policy            Write Through
Force WB no battery     DESATIVADO
Hot Spare               nenhum
```

### Recomendação

**Não modificar o RAID durante a reinstalação do Ubuntu.**

A reinstalação deve apagar/recriar somente as estruturas do sistema operacional dentro do Virtual Disk apresentado pelo PERC.

Não executar no controlador:

```text
Delete Virtual Disk
Initialize Virtual Disk
Fast Init
Clear Configuration
Factory Default
Force WB with no battery
```

---

## 9. Estado de prontidão atualizado

### Pronto para reinstalação

- RAID 5 confirmado;
- estado `Optimal`;
- três discos `Online`;
- Virtual Disk definido;
- boot pelo VD configurado;
- SEL limpo;
- relógio SEL corrigido;
- hostname desejado definido;
- usuário administrador definido;
- Ubuntu 24.04 já comprovadamente funcional.

### Manutenção posterior recomendada

- substituir/avaliar BBU do PERC;
- monitorar o disco físico com grown defects e erros não corrigidos;
- aumentar RAM;
- ligar as duas fontes quando o servidor sair da bancada;
- manter backup externo;
- avaliar BIOS/firmware somente em procedimento separado.

---

# 10. Observação pedagógica para os alunos

Esta tela é particularmente útil para explicar a diferença entre:

```text
disco físico
RAID
Virtual Disk
particionamento
LVM
sistema de arquivos
```

Neste servidor:

```text
3 discos físicos SAS
        ↓
PERC 5/i
        ↓
RAID 5
        ↓
Virtual Disk 0 = 557,750 GB
        ↓
Linux enxerga /dev/sda
        ↓
partições GPT
        ↓
LVM
        ↓
ext4
        ↓
diretórios /, /srv, /home etc.
```

O PERC não sabe que existe Ubuntu, Docker ou `/srv`.

O Ubuntu, por sua vez, não vê diretamente três discos independentes para uso normal: ele recebe do PERC o Virtual Disk RAID já consolidado.

Essa separação deve ser explicitamente ensinada durante a reinstalação.
