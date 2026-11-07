# Coolify — Backup do plano de controle para Cloudflare R2

---

## Visao geral

O Coolify tem **backup nativo** para os bancos das aplicacoes (PostgreSQL, MySQL,
MariaDB, MongoDB, ClickHouse e SQLite), com upload para qualquer storage
S3-compativel, incluindo o R2. Use o backup nativo para os bancos gerenciados.

O backup nativo **nao cobre** o plano de controle do Coolify:

| Item | Onde fica | Coberto por este script |
|---|---|---|
| Banco interno do Coolify (projetos, apps, usuarios, settings) | volume Docker `coolify-db` | sim (`pg_dump`) |
| `APP_KEY`, senhas e chaves SSH | `/data/coolify/source/.env` e `/data/coolify/ssh` | sim |
| Configuracoes geradas de apps/bancos/servicos/proxy | `/data/coolify/*` | sim |
| Dados das aplicacoes e bancos gerenciados | volumes Docker dos recursos | nao (use o backup nativo) |

O `backup-instancia.sh` gera um unico pacote criptografado com:

- `db.dmp` — `pg_dump --format=custom` do container `coolify-db`
- `data.tar.gz` — `/data/coolify`, sem `backups`, logs e `ssh/mux`

e envia `coolify-instancia-AAAAmmdd_HHMMSS.tar.enc` + `.sha256` para o R2.

---

## Pre-requisitos

- [ ] Coolify instalado em `/data/coolify` e container `coolify-db` em execucao
- [ ] Bucket no Cloudflare R2
- [ ] Token R2 com permissao **Object Read & Write** no bucket
- [ ] AWS CLI, OpenSSL, Docker e `flock` instalados
- [ ] Acesso root (cron e leitura de `/data/coolify`)

```bash
sudo apt update
sudo apt install -y awscli openssl util-linux
```

> O pacote `awscli` do Debian e suficiente. Se preferir o AWS CLI v2, instale
> pelo instalador oficial da AWS.

---

## Instalacao

O instalador cria o script de backup, o de restauracao, a configuracao, a
passphrase, o cron e o logrotate:

```bash
sudo ./scripts/coolify/backup/instala-backup-instancia.sh
```

Ele pergunta os dados do R2 que estiverem faltando. Para nao perguntar nada:

```bash
sudo ./scripts/coolify/backup/instala-backup-instancia.sh -y
```

Outras opcoes: `--help` (`--test`, `--skip-deps`, `--no-cron`, `--no-logrotate`,
`--schedule`, `--config`, `--dest`, `--force`).

Passos equivalentes, caso prefira instalar manualmente:

```bash
sudo install -m 700 scripts/coolify/backup/backup-instancia.sh /usr/local/bin/coolify-backup.sh
sudo install -m 700 scripts/coolify/backup/restore-instancia.sh /usr/local/bin/coolify-restore.sh
sudo install -m 600 scripts/coolify/backup/coolify-backup.env.example /etc/coolify-backup.env
openssl rand -base64 48 | sudo tee /etc/coolify-backup.passphrase >/dev/null
sudo chmod 600 /etc/coolify-backup.passphrase
```

Preencha em `/etc/coolify-backup.env`:

```bash
R2_BUCKET="coolify-backups"
R2_ENDPOINT="https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
R2_PREFIX="instancia"
AWS_ACCESS_KEY_ID="..."
AWS_SECRET_ACCESS_KEY="..."
```

O endpoint inclui o esquema, no formato
`https://<ACCOUNT_ID>.r2.cloudflarestorage.com` (o script usa o valor como esta).

> Sem a passphrase nao existe restore. Se ela for perdida, os backups antigos
> continuam no R2, mas nao podem ser descriptografados.

### Cron

O instalador ja cria `/etc/cron.d/coolify-backup`. Para criar manualmente:

```cron
30 3 * * * root flock -n /var/lock/coolify-backup.lock /usr/local/bin/coolify-backup.sh >> /var/log/coolify-backup.log 2>&1
```

```bash
sudo chmod 644 /etc/cron.d/coolify-backup
```

`flock -n` evita duas execucoes simultaneas (cron + execucao manual).

### Rotacao do log

O cron usa `>> /var/log/coolify-backup.log`: cada execucao acrescenta a saida ao
mesmo arquivo. Sem rotacao o arquivo cresce indefinidamente e pode encher o
disco. O `logrotate` (ja incluso no Debian) resolve isso: periodicamente ele
renomeia o log atual, cria um novo vazio e comprime os antigos.

O instalador cria `/etc/logrotate.d/coolify-backup` automaticamente. Para criar
manualmente, use:

```
/var/log/coolify-backup.log {
    weekly               # rotaciona apos ~7 dias
    rotate 8             # mantem 8 arquivos antigos (~8 semanas)
    compress             # comprime os antigos (.gz)
    missingok            # nao falha se o log nao existir
    notifempty           # ignora arquivo vazio
    create 0640 root adm # recria o log com essas permissoes
}
```

Resultado em `/var/log`:

```
coolify-backup.log        # atual
coolify-backup.log.1.gz   # rotacao anterior
...
coolify-backup.log.8.gz   # mais antiga mantida
```

O `logrotate.timer` do systemd dispara o logrotate diariamente; o `weekly` e
avaliado a cada disparo. Para conferir sem alterar nada e para forcar um teste:

```bash
sudo logrotate -d /etc/logrotate.d/coolify-backup
sudo logrotate -f /etc/logrotate.d/coolify-backup
```

Como o cron abre e fecha o arquivo a cada execucao, nao e necessario
`copytruncate` (usado apenas quando um processo mantem o arquivo aberto).

### Retencao no R2

A retencao fica no bucket, nao no script:

1. Cloudflare Dashboard → R2 → bucket → **Settings → Object lifecycle rules**
2. Adicione uma regra com prefixo `instancia/`
3. Ex.: **Delete objects after 30 days**

Antes de criar a regra, confira o prefixo usado pelo backup nativo do Coolify e
nao aplique a regra a ele, para nao apagar copias que o Coolify ainda gerencia.

---

## Teste

```bash
sudo flock -n /var/lock/coolify-backup.lock /usr/local/bin/coolify-backup.sh
```

Confira no R2:

- `instancia/coolify-instancia-*.tar.enc`
- `instancia/coolify-instancia-*.tar.enc.sha256`

Valide o pacote:

```bash
aws --region auto --endpoint-url "$R2_ENDPOINT" \
  s3 cp "s3://$R2_BUCKET/instancia/ARQUIVO.tar.enc" .
aws --region auto --endpoint-url "$R2_ENDPOINT" \
  s3 cp "s3://$R2_BUCKET/instancia/ARQUIVO.tar.enc.sha256" .

sha256sum -c ARQUIVO.tar.enc.sha256
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in ARQUIVO.tar.enc -out ARQUIVO.tar \
  -pass file:/etc/coolify-backup.passphrase

mkdir -p /tmp/coolify-restore
tar -xf ARQUIVO.tar -C /tmp/coolify-restore
docker exec -i coolify-db pg_restore --list < /tmp/coolify-restore/db.dmp | head
```

O `pg_restore --list` prova que o dump e valido. Faca tambem um restore real em
uma instancia descartavel antes de considerar o backup confiavel.

---

## Restauracao

O `restore-instancia.sh` automatiza os passos 2 a 5 deste guia (baixar/conferir,
descriptografar, restaurar banco e arquivos e subir os containers):

```bash
# mesma maquina
sudo ./scripts/coolify/backup/restore-instancia.sh --download

# maquina nova (nao sobrescreve source/.env; copia apenas o APP_KEY)
sudo ./scripts/coolify/backup/restore-instancia.sh --download --mode new
```

Tambem aceita `--file ARQUIVO.tar.enc` para um pacote local e `--r2-key CHAVE`
para escolher um backup especifico. Veja `--help` para todas as opcoes
(`--no-start`, `--keep`, `--skip-verify`, `--yes`, `--work-dir`,
`--passphrase-file`).

O instalador copia o restore para `/usr/local/bin/coolify-restore.sh`, entao
tambem funciona como `sudo coolify-restore.sh --download`.

O script valida o dump com `pg_restore --list` antes de alterar o banco e exige a
confirmacao `RESTAURAR`. Ele tambem reautoriza em `/root/.ssh/authorized_keys` as
chaves restauradas de `/data/coolify/ssh/keys`, necessarias para o Coolify
acessar o host como `root@host.docker.internal`.

Os passos manuais abaixo continuam validos para conferencia ou restauracao
parcial.

### 1. Preparar o destino

Instale o Coolify (de preferencia na mesma versao) e nao configure nada.
Mantenha os containers no ar para o passo do banco.

### 2. Baixar, conferir e descriptografar

```bash
aws --region auto --endpoint-url "$R2_ENDPOINT" \
  s3 cp "s3://$R2_BUCKET/instancia/ARQUIVO.tar.enc" .
aws --region auto --endpoint-url "$R2_ENDPOINT" \
  s3 cp "s3://$R2_BUCKET/instancia/ARQUIVO.tar.enc.sha256" .

sha256sum -c ARQUIVO.tar.enc.sha256
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in ARQUIVO.tar.enc -out ARQUIVO.tar \
  -pass file:/etc/coolify-backup.passphrase

mkdir -p /tmp/coolify-restore
tar -xf ARQUIVO.tar -C /tmp/coolify-restore
```

### 3. Restaurar o banco interno

Pare o painel e o Redis, mas **mantenha o `coolify-db` rodando**:

```bash
docker stop coolify coolify-redis

DB_USER="$(docker exec coolify-db printenv POSTGRES_USER)"
DB_NAME="$(docker exec coolify-db printenv POSTGRES_DB)"

docker exec -i coolify-db pg_restore \
  --clean --if-exists --exit-on-error --no-acl --no-owner \
  --username="$DB_USER" --dbname="$DB_NAME" \
  < /tmp/coolify-restore/db.dmp
```

### 4. Restaurar arquivos

Extraia o tar de dados em um diretorio temporario:

```bash
sudo mkdir -p /tmp/coolify-files
sudo tar -xzf /tmp/coolify-restore/data.tar.gz -C /tmp/coolify-files
```

**Mesma maquina:** copie por cima de `/data/coolify` e ajuste o dono:

```bash
sudo cp -a /tmp/coolify-files/coolify/. /data/coolify/
sudo chown -R 9999:root /data/coolify
```

**Maquina nova:** nao sobrescreva o `/data/coolify/source` da instalacao nova.
Copie apenas:

```bash
sudo cp -a /tmp/coolify-files/coolify/ssh/keys /data/coolify/ssh/
sudo cp -a /tmp/coolify-files/coolify/applications /data/coolify/ 2>/dev/null || true
sudo cp -a /tmp/coolify-files/coolify/databases /data/coolify/ 2>/dev/null || true
sudo cp -a /tmp/coolify-files/coolify/services /data/coolify/ 2>/dev/null || true
sudo chown -R 9999:root /data/coolify
```

E copie **somente o `APP_KEY`** do `.env` do backup para o `.env` atual.
Mantenha `DB_PASSWORD` e `REDIS_PASSWORD` da instalacao nova.

### 5. Subir e validar

```bash
cd /data/coolify/source
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.prod.yml \
  up -d --remove-orphans
```

Se existir `docker-compose.custom.yml`, inclua tambem
`-f docker-compose.custom.yml`. Rodar so `docker compose up -d` falha com
`service "coolify" has neither an image nor a build context specified`, porque a
imagem do servico `coolify` esta no `docker-compose.prod.yml`.

Faca login, confira os recursos e rode um deploy de teste.

---

## Solucao de problemas

| Sintoma | Causa provavel / solucao |
|---|---|
| `comando ausente: aws` | Instale o AWS CLI ou ajuste o `PATH` |
| `403` no upload | Token sem `Object Read & Write` ou com escopo errado |
| `SignatureDoesNotMatch` / erro de regiao | Confirme o endpoint e use `--region auto` |
| `coolify-db nao esta rodando` | `docker start coolify-db` e rode de novo |
| `dump vazio` | `POSTGRES_USER`/`POSTGRES_DB` ausentes no container |
| `tamanho remoto difere do local` | Reenvie; verifique espaco e conectividade |
| `bad decrypt` | Passphrase errada ou `-iter` diferente de `200000` |
| Cron nao gera arquivo | Veja `/var/log/coolify-backup.log`; confira o `PATH` |
| Backup nativo sumiu do R2 | Regra de lifecycle aplicada a prefixo errado |
| `root@host.docker.internal: Permission denied (publickey)` | A chave restaurada não está em `/root/.ssh/authorized_keys`; rode o `restore-instancia.sh` de novo ou autorize a chave manualmente |

---

## Relacao com `backup-coolify.sh`

O `backup-coolify.sh` e a versao completa (fallback rclone/aws, retencao manual,
mensagens). O `backup-instancia.sh` e a versao enxuta recomendada para cron.
Os dois nao devem rodar juntos: escolha um e mantenha o outro apenas como
referencia.
