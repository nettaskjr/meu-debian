# 1. Script
sudo install -m 700 backup-instancia.sh /usr/local/bin/coolify-backup.sh

# 2. Configuracao
sudo install -m 600 coolify-backup.env.example /etc/coolify-backup.env

# 3. Passphrase (guarde tambem no gerenciador de senhas)
openssl rand -base64 48 | sudo tee /etc/coolify-backup.passphrase >/dev/null
sudo chmod 600 /etc/coolify-backup.passphrase

# 4. Edita o arquivo .env
sudo editor /etc/coolify-backup.env
