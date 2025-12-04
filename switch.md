# 📘 **Guia Completo de Configuração Inicial do Huawei S5720 para Acesso Remoto (SSH)**

Este documento descreve, passo a passo, como realizar a configuração inicial de um switch **Huawei S5720**, começando pelo primeiro acesso via console, criação de senha, criação de usuário administrador, habilitação de SSH e salvamento das configurações.

Esse procedimento foi testado e validado com base na sessão real apresentada no terminal.

---

# 🟦 **1. Primeiro acesso via console**

Ao conectar no switch via porta **Console**, a primeira tela exibida será:

```
An initial password is required for the first login via the console.
Continue to set it? [Y/N]:
```

### ✔️ Digite `Y` e pressione Enter.

---

# 🟦 **2. Criar a senha inicial obrigatória**

O switch solicitará uma senha entre **8 e 16 caracteres**, contendo pelo menos **duas categorias**:

* letras minúsculas
* letras maiúsculas
* números
* caracteres especiais

Exemplo da saída real:

```
Please configure the login password (8-16)
Enter Password:
Error: The password length must range from 8 to 16.
```

e depois:

```
Error: The password must consist of at least 2 types of characters, including lowercase letters, uppercase letters, numerals and special characters.
```

Quando uma senha válida for aceita:

```
Enter Password:
Confirm Password:
Warning: The authentication mode was changed to password authentication and the user level was changed to 15 on con0 at the first user login.
Warning: There is a risk on the user-interface which you login through. Please change the configuration of the user-interface as soon as possible.
```

O prompt aparecerá:

```
<HUAWEI>
```

Isso significa que você está no modo **usuário**.

---

# 🟦 **3. Entrar no modo de configuração global**

Digite:

```
<HUAWEI>system-view
```

Resposta:

```
Enter system view, return user view with Ctrl+Z.
[HUAWEI]
```

---

# 🟦 **4. Entrar no modo AAA e criar o usuário administrador**

Digite:

```
[HUAWEI]aaa
```

Saída:

```
[HUAWEI-aaa]
```

Agora crie o usuário `admin`:

```
local-user admin password irreversible-cipher ramones1234
```

Saída real:

```
Info: After changing the rights (...) The change takes effect to users who go online after the change.
```

---

## 4.1 Definir nível de privilégio máximo (15)

```
local-user admin privilege level 15
```

Saída:

```
Info: After changing the rights (...)
```

---

## 4.2 Permitir acesso por SSH, Telnet e Console (terminal)

```
local-user admin service-type ssh telnet terminal
```

Saída:

```
Warning: The user access modes include Telnet, FTP, or HTTP, so security risks exist.
Info: After changing the rights (...)
```

---

## 4.3 Sair do AAA

```
quit
```

O prompt volta:

```
[HUAWEI]
```

---

# 🟦 **5. Habilitar o servidor SSH (Stelnet)**

Digite:

```
stelnet server enable
```

Saída:

```
Info: Succeeded in starting the Stelnet server.
```

---

# 🟦 **6. Criar usuário SSH e definir autenticação**

```
ssh user admin
ssh authentication-type default password
```

Saída:

```
Info: Succeeded in adding a new SSH user.
```

---

# 🟦 **7. Criar par de chaves RSA**

```
rsa local-key-pair create
```

Saída típica:

```
The key name will be: HUAWEI_Host
The range of public key size is (512 ~ 2048).
Input the bits in the modulus[default = 2048]:
Generating keys...
....+++++
........................++
....++++
...........++
```

Aguarde a conclusão.

---

# 🟦 **8. Configurar as linhas VTY para permitir apenas SSH**

Entre nas linhas VTY:

```
user-interface vty 0 4
```

A saída será:

```
[HUAWEI-ui-vty0-4]
```

Agora configure:

```
authentication-mode aaa
protocol inbound ssh
```

Saídas:

```
Warning: The level of the user-interface(s) will be the default level of AAA users [...]
```

Finalize:

```
quit
```

---

# 🟦 **9. (Opcional) Configurar IP para acesso remoto**

⚠️ Este passo será feito posteriormente ao definir o cluster.
Por enquanto, o switch já está preparado para SSH, bastando definir um IP depois.

---

# 🟦 **10. Salvar a configuração**

Muito importante! Sem isso, tudo é perdido ao reiniciar.

```
save
```

Saída real:

```
The current configuration will be written to the device.
Are you sure to continue?[Y/N]Y
Info: Please input the file name ( *.cfg, *.zip ) [vrpcfg.zip]:
```

Pressione Enter para usar o nome padrão.

---

# 🟩 **Status final: sistema configurado**

Neste ponto, você já:

* criou uma senha inicial
* entrou no modo de configuração
* criou um usuário administrador
* habilitou SSH
* configurou as linhas VTY
* gerou as chaves RSA
* salvou a configuração

O switch está pronto para receber endereço IP e ser integrado ao cluster.

---
