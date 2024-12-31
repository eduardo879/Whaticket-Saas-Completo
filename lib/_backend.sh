#!/bin/bash
#
# Script para instalação e configuração do backend do Whaticket SaaS Completo
# https://github.com/andrew890074/Whaticket-Saas-Completo
#
# **AVISO:** Este script é uma versão melhorada do script original, mas ainda requer revisão e adaptação
# para o seu ambiente específico. Use por sua conta e risco.
#
# **SEGURANÇA:** Este script lida com informações sensíveis. **NÃO** o execute em produção
# sem antes revisar e entender completamente o que ele faz.
#

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY_LIGHT='\033[0;37m'
NC='\033[0m' # No Color

# Variáveis de ambiente - **CONFIGURE ESTAS VARIÁVEIS CORRETAMENTE**
db_user="whaticketuser"
db_name="whaticketdb"
backend_hostname="seu_dominio.com"  # Substitua pelo seu domínio (ou IP para testes)
frontend_url="https://seu_dominio.com"  # Substitua pelo seu domínio (ou IP para testes)
# Outras variáveis como as de email, GerenciaNet, Facebook, etc. devem ser configuradas no .env posteriormente

# Função para imprimir banners
print_banner() {
  printf "${BLUE}###############################################################################${NC}\n"
  printf "${BLUE}# $1${NC}\n"
  printf "${BLUE}###############################################################################${NC}\n"
}

# Função para gerar senhas aleatórias
generate_password() {
  openssl rand -base64 32
}

# Função para verificar se um comando foi executado com sucesso
check_command() {
  if [ $? -ne 0 ]; then
    printf "${RED}ERRO: O comando anterior falhou. Abortando.${NC}\n"
    exit 1
  fi
}

# --- Início da Configuração ---

# Atualiza o sistema
print_banner "Atualizando o sistema"
sudo apt update
check_command
sudo apt upgrade -y
check_command

# Instala dependências
print_banner "Instalando dependências"
sudo apt install -y ca-certificates curl gnupg mysql-server nginx git
check_command

# Configura o banco de dados MySQL
print_banner "Configurando o banco de dados MySQL"
db_pass=$(generate_password)
sudo mysql <<EOF
CREATE DATABASE ${db_name};
CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
check_command
printf "${YELLOW}Senha do banco de dados (guarde em local seguro): ${db_pass}${NC}\n"

# Cria o usuário para a aplicação
print_banner "Criando usuário para a aplicação"
sudo useradd -m -s /bin/bash deployautomatizaai
check_command

# Instala o Node.js 18 LTS
print_banner "Instalando Node.js 18 LTS"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt-get update
sudo apt-get install -y nodejs
check_command

# Instala o PM2
print_banner "Instalando o PM2"
sudo npm install -g pm2
check_command

# Instala o Certbot
print_banner "Instalando o Certbot"
sudo apt install -y certbot python3-certbot-nginx
check_command

# Instala o Google Chrome
print_banner "Instalando o Google Chrome"
sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y google-chrome-stable
check_command

# --- Configuração do Whaticket ---
print_banner "Configurando o Whaticket"
cd /opt
sudo git clone https://github.com/andrew890074/Whaticket-Saas-Completo.git
sudo chown -R deployautomatizaai:deployautomatizaai /opt/Whaticket-Saas-Completo
check_command

# --- Configuração do Backend ---
print_banner "Configurando o Backend"
cd /opt/Whaticket-Saas-Completo/whaticket/backend

# Instala dependências do backend com npm ci
print_banner "Instalando dependências do backend"
sudo -u deployautomatizaai npm ci
check_command

# Configura as variáveis de ambiente do backend
print_banner "Configurando variáveis de ambiente do backend"
sudo mv .env.example .env
jwt_secret=$(generate_password)
jwt_refresh_secret=$(generate_password)
sudo sed -i "s|DB_USER=.*|DB_USER=${db_user}|g" .env
sudo sed -i "s|DB_PASS=.*|DB_PASS=${db_pass}|g" .env
sudo sed -i "s|DB_NAME=.*|DB_NAME=${db_name}|g" .env
sudo sed -i "s|BACKEND_URL=.*|BACKEND_URL=https://${backend_hostname}|g" .env
sudo sed -i "s|FRONTEND_URL=.*|FRONTEND_URL=${frontend_url}|g" .env
sudo sed -i "s|JWT_SECRET=.*|JWT_SECRET=${jwt_secret}|g" .env
sudo sed -i "s|JWT_REFRESH_SECRET=.*|JWT_REFRESH_SECRET=${jwt_refresh_secret}|g" .env
sudo sed -i "s|REDIS_URI=.*|REDIS_URI=redis://:${db_pass}@127.0.0.1:6379|g" .env
sudo chown deployautomatizaai:deployautomatizaai .env
check_command

# Executa as migrações do banco de dados
print_banner "Executando migrações do banco de dados"
sudo -u deployautomatizaai npx sequelize db:migrate
check_command

# --- Configuração do Frontend ---
print_banner "Configurando o Frontend"
cd ../frontend

# Instala dependências do frontend com npm ci
print_banner "Instalando dependências do frontend"
sudo -u deployautomatizaai npm ci
check_command

# Configura as variáveis de ambiente do frontend
print_banner "Configurando variáveis de ambiente do frontend"
sudo mv .env.example .env
sudo sed -i "s|VITE_BASE_URL=.*|VITE_BASE_URL=https://${backend_hostname}/api|g" .env
sudo chown deployautomatizaai:deployautomatizaai .env
check_command

# Compila o frontend para produção
print_banner "Compilando o frontend para produção"
sudo -u deployautomatizaai npm run build
check_command

# --- Configuração do Nginx ---
print_banner "Configurando o Nginx"
sudo rm /etc/nginx/sites-enabled/default
sudo tee /etc/nginx/sites-available/whaticket <<EOF
server {
    listen 80;
    server_name ${backend_hostname} www.${backend_hostname};

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        try_files \$uri \$uri/ /index.html;
    }

    location /socket.io {
        proxy_pass http://localhost:8080/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
    }

    location /api {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
    }

    location /static {
        root /opt/Whaticket-Saas-Completo/whaticket/frontend/dist;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
sudo ln -s /etc/nginx/sites-available/whaticket /etc/nginx/sites-enabled/
check_command
sudo nginx -t
check_command
sudo systemctl restart nginx
check_command

# --- Configuração do SSL (HTTPS) ---
print_banner "Configurando SSL (HTTPS) com Certbot"
sudo certbot --nginx -d ${backend_hostname} -d www.${backend_hostname} --redirect
check_command

# --- Configuração do PM2 ---
print_banner "Configurando o PM2"
cd /opt/Whaticket-Saas-Completo/whaticket/backend
sudo -u deployautomatizaai pm2 start npm --name "backend" -- run start
check_command
sudo -u deployautomatizaai pm2 startup systemd
check_command
sudo -u deployautomatizaai pm2 save
check_command

# --- Configuração do Firewall ---
print_banner "Configurando o Firewall (UFW)"
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
check_command

printf "${GREEN}Instalação e configuração concluídas!${NC}\n"
printf "${YELLOW}Acesse o Whaticket em https://${backend_hostname}${NC}\n"
printf "${YELLOW}Lembre-se de configurar as variáveis de ambiente restantes no arquivo /opt/Whaticket-Saas-Completo/whaticket/backend/.env${NC}\n"