Para impedir que um notebook com **Debian** entre em suspensão ou hibernação, mesmo sem login (no greeter do GDM), é necessário combater as configurações do gerenciador de energia do ambiente gráfico e do sistema systemd. A solução mais eficaz envolve **editar o arquivo de configuração do GDM** para desativar a suspensão automática na tela de login e **mascarar os serviços de suspensão** do systemd.

### 1. Desativar Suspensão no Greeter do GDM
O **Debian** usa o **GDM3** como gerenciador de login por padrão. A suspensão automática é frequentemente controlada por este greeter.

1. Edite o arquivo `/etc/gdm3/greeter.dconf-defaults`:
   ```bash
   sudo nano /etc/gdm3/greeter.dconf-defaults
   ```
2. Localize ou adicione a seção `[org/gnome/settings-daemon/plugins/power]` e configure os valores para `0` (tempo) e `'nothing'` (ação), descomentando as linhas se necessário:
   ```ini
   # Automatic suspend
   # =================
   [org/gnome/settings-daemon/plugins/power]
   sleep-inactive-ac-timeout=0
   sleep-inactive-ac-type='nothing'
   sleep-inactive-battery-timeout=0
   sleep-inactive-battery-type='nothing'
   ```
3. Recarregue o serviço do GDM ou reinicie o sistema:
   ```bash
   sudo systemctl reload gdm3
   # Ou, se não funcionar, reinicie:
   sudo reboot
   ```

### 2. Desativar Suspensão via Systemd
Para garantir que o sistema não suspenda mesmo após o login ou via comandos diretos, mascare os alvos de suspensão do **systemd**.

1. Execute o comando para mascarar os serviços:
   ```bash
   sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
   ```
2. Verifique o status para confirmar:
   ```bash
   systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target
   ```

### 3. Ignorar Fechamento da Tampa (Opcional)
Se o notebook suspender ao fechar a tampa, edite o arquivo `/etc/systemd/logind.conf`:

1. Abra o arquivo:
   ```bash
   sudo nano /etc/systemd/logind.conf
   ```
2. Adicione ou modifique as seguintes linhas:
   ```ini
   [Login]
   HandleLidSwitch=ignore
   HandleLidSwitchDocked=ignore
   ```
3. Reinicie o serviço `systemd-logind`:
   ```bash
   sudo systemctl restart systemd-logind
   ```

**Nota:** O método de edição do `/etc/gdm3/greeter.dconf-defaults` é crucial para o caso específico de **sem login**, pois o `systemctl mask` afeta principalmente o sistema após a inicialização completa do ambiente de usuário. A combinação dos dois métodos garante a máxima cobertura.

### 4. Verificação
Para confirmar que as alterações foram aplicadas com sucesso:

Verifique o status dos alvos de suspensão (devem aparecer como "masked"):
   ```bash
   systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target
   ```

Monitore os logs ao fechar a tampa ou aguardar o tempo de inatividade para garantir que nenhum evento de suspensão seja disparado:
   ```bash
   journalctl -f
   ```

### 5. Reversão (Caso necessário)
Para reativar a suspensão e hibernação no futuro:

   ```bash
   sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
   sudo systemctl daemon-reload
   ```

E reverta as alterações nos arquivos `/etc/gdm3/greeter.dconf-defaults` e `/etc/systemd/logind.conf`.