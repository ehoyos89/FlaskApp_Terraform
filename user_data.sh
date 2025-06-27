#!/bin/bash
# user_data.sh
# Este script se ejecuta como root.

# Función para logging
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a /var/log/user-data.log
}

log "Iniciando script de User Data para ${project_name}..."

# Redireccionar toda la salida al log
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

# Configurar variables de entorno
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
export HOME="/root"

log "Esperando que el sistema esté completamente inicializado..."
sleep 30

# Detectar la distribución
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
  log "Sistema operativo detectado: $OS"
fi

# Actualizar el sistema según la distribución
log "Actualizando el sistema..."
if [[ "$OS" == *"Amazon Linux"* ]]; then
  yum update -y
  yum install -y python3 python3-pip mysql git aws-cli jq wget curl

  # Instalar amazon-linux-extras si está disponible
  if command -v amazon-linux-extras &>/dev/null; then
    amazon-linux-extras install epel -y
    log "EPEL instalado via amazon-linux-extras"
  fi

  # Instalar stress (opcional para testing)
  yum install -y stress

elif [[ "$OS" == *"Ubuntu"* ]]; then
  apt-get update -y
  apt-get install -y python3 python3-pip mysql-client git awscli jq wget curl stress

elif [[ "$OS" == *"Red Hat"* ]] || [[ "$OS" == *"CentOS"* ]]; then
  yum update -y
  yum install -y python3 python3-pip mysql git aws-cli jq wget curl stress
else
  log "Distribución no reconocida, intentando con yum..."
  yum update -y
  yum install -y python3 python3-pip mysql git aws-cli jq wget curl stress
fi

# Verificar instalaciones críticas
log "Verificando instalaciones..."
for cmd in git python3 aws jq pip3; do
  if command -v $cmd &>/dev/null; then
    log "$cmd instalado correctamente: $(which $cmd)"
    case $cmd in
    git | python3 | aws | jq)
      $cmd --version 2>&1 | head -1 | while read line; do log "$line"; done
      ;;
    pip3)
      $cmd --version 2>&1 | head -1 | while read line; do log "$line"; done
      ;;
    esac
  else
    log "ERROR: $cmd no está instalado"
    exit 1
  fi
done

# Configurar AWS CLI
log "Configurando AWS CLI..."
aws configure set default.region ${aws_region}
aws configure set default.output json

# Verificar conectividad a GitHub
log "Verificando conectividad a GitHub..."
if curl -s --connect-timeout 10 https://github.com >/dev/null; then
  log "Conectividad a GitHub: OK"
else
  log "ERROR: No hay conectividad a GitHub"
  exit 1
fi

# Crear directorio de destino
TARGET_DIR="/home/ec2-user/flask-app"
log "Creando directorio: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# Clonar el repositorio con reintentos
log "Clonando repositorio de GitHub..."
REPO_URL="https://github.com/ehoyos89/FlaskApp.git"
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  log "Intento de clonación #$((RETRY_COUNT + 1))"

  if git clone "$REPO_URL" "$TARGET_DIR"; then
    log "Repositorio clonado exitosamente"
    break
  else
    log "Error en la clonación, intento #$((RETRY_COUNT + 1)) fallido"
    RETRY_COUNT=$((RETRY_COUNT + 1))

    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      log "Esperando 10 segundos antes del siguiente intento..."
      sleep 10
      rm -rf "$TARGET_DIR"
      mkdir -p "$TARGET_DIR"
    else
      log "ERROR: Falló la clonación después de $MAX_RETRIES intentos"
      exit 1
    fi
  fi
done

# Cambiar ownership del directorio
log "Cambiando ownership del directorio de la aplicación..."
chown -R ec2-user:ec2-user /home/ec2-user/flask-app

# Navegar al directorio de la aplicación
log "Navegando al directorio de la aplicación..."
cd "$TARGET_DIR"

# Instalar dependencias de Python
log "Instalando dependencias de Python..."
if [ -f "requirements.txt" ]; then
  log "Archivo requirements.txt encontrado, instalando dependencias..."
  python3 -m pip install --upgrade pip
  pip3 install -r requirements.txt
  log "Dependencias de Python instaladas desde requirements.txt"
else
  log "Warning: requirements.txt no encontrado"
fi

# Instalar Gunicorn
log "Instalando Gunicorn..."
pip3 install gunicorn
if command -v gunicorn &>/dev/null; then
  log "Gunicorn instalado correctamente: $(which gunicorn)"
  gunicorn --version | while read line; do log "$line"; done
else
  log "ERROR: Gunicorn no se instaló correctamente"
  exit 1
fi

# Obtener secretos de AWS Secrets Manager
log "Obteniendo secretos de AWS Secrets Manager..."

# Función para obtener secretos con reintentos - CORREGIDA
get_secret() {
  local secret_arn=$1
  local key=$2
  local max_retries=3
  local retry_count=0

  while [ $retry_count -lt $max_retries ]; do
    # Escribir logs a stderr para evitar que se mezclen con el resultado
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Obteniendo secreto $key, intento #$((retry_count + 1))" >&2

    local secret_value=$(aws secretsmanager get-secret-value --secret-id "$secret_arn" --query SecretString --output text 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$secret_value" ]; then
      local result=$(echo "$secret_value" | jq -r ".$key" 2>/dev/null)
      if [ $? -eq 0 ] && [ "$result" != "null" ] && [ -n "$result" ]; then
        # Solo el resultado va a stdout
        echo "$result"
        return 0
      fi
    fi

    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Error obteniendo secreto $key, reintentando en 5 segundos..." >&2
      sleep 5
    fi
  done

  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: No se pudo obtener el secreto $key después de $max_retries intentos" >&2
  return 1
}

# Obtener secretos - capturar solo el valor, no los logs
log "Obteniendo secreto de username de la base de datos..."
DB_USERNAME=$(get_secret "${db_username_secret_arn}" "username")
if [ $? -ne 0 ]; then
  log "ERROR: No se pudo obtener el username de la base de datos"
  exit 1
fi
log "Username de BD obtenido exitosamente"

log "Obteniendo secreto de password de la base de datos..."
DB_PASSWORD=$(get_secret "${db_password_secret_arn}" "password")
if [ $? -ne 0 ]; then
  log "ERROR: No se pudo obtener el password de la base de datos"
  exit 1
fi
log "Password de BD obtenido exitosamente"

log "Obteniendo secreto de Flask secret key..."
FLASK_SECRET=$(get_secret "${flask_secret_key_secret_arn}" "secret_key")
if [ $? -ne 0 ]; then
  log "ERROR: No se pudo obtener el Flask secret key"
  exit 1
fi
log "Flask secret key obtenido exitosamente"

log "Todos los secretos obtenidos exitosamente"

# Crear directorio para variables de entorno del servicio
log "Configurando servicio systemd..."
mkdir -p /etc/systemd/system/flask_app.service.d

# Configurar variables de entorno para la aplicación
log "Creando archivo de configuración de entorno..."
db_host_only=$(echo "$db_endpoint" | cut -d':' -f1)
cat >/etc/systemd/system/flask_app.service.d/environment.conf <<EOF
[Service]
Environment="PHOTOS_BUCKET=${photos_bucket}"
Environment="DATABASE_HOST=${db_host_only}"
Environment="DATABASE_USER=$DB_USERNAME"
Environment="DATABASE_PASSWORD=$DB_PASSWORD"
Environment="DATABASE_PORT=3306"
Environment="DATABASE_DB_NAME=${db_name}"
Environment="FLASK_SECRET=$FLASK_SECRET"
EOF

# Verificar el contenido del archivo generado
log "Verificando archivo de configuración generado:"
cat /etc/systemd/system/flask_app.service.d/environment.conf | while read line; do log "CONFIG: $line"; done

# También crear el archivo de perfil para depuración (opcional)
log "Creando archivo de perfil de entorno..."
cat >/etc/profile.d/flask_app_env.sh <<EOF
export PHOTOS_BUCKET="${photos_bucket}"
export DATABASE_HOST="${db_host_only}"
export DATABASE_USER="$DB_USERNAME"
export DATABASE_PASSWORD="$DB_PASSWORD"
export DATABASE_PORT="3306"
export DATABASE_DB_NAME="${db_name}"
export FLASK_SECRET="$FLASK_SECRET"
EOF

# Iniciando base de datos
log "Iniciando base de datos..."
cat database_create_tables.sql | mysql -h $DATABASE_HOST -u $DATABASE_USER -p$DATABASE_PASSWORD $DATABASE_DB_NAME

# Crear un servicio systemd para Gunicorn
log "Creando servicio systemd para Flask..."
cat >/etc/systemd/system/flask_app.service <<EOF
[Unit]
Description=Gunicorn instance to serve flask_app
After=network.target

[Service]
User=ec2-user
Group=ec2-user
WorkingDirectory=/home/ec2-user/flask-app
ExecStart=/usr/local/bin/gunicorn --workers 4 --bind 0.0.0.0:8000 application:application
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Verificar que el archivo de aplicación existe
if [ ! -f "/home/ec2-user/flask-app/application.py" ]; then
  log "Warning: application.py no encontrado en el directorio de la aplicación"
  ls -la /home/ec2-user/flask-app/ | while read line; do log "$line"; done
fi

# Recargar systemd y habilitar/iniciar el servicio
log "Recargando systemd daemon..."
systemctl daemon-reload

log "Habilitando servicio flask_app..."
systemctl enable flask_app

# Esperar un momento antes de iniciar el servicio
log "Esperando antes de iniciar el servicio..."
sleep 5

log "Iniciando servicio flask_app..."
systemctl start flask_app

# Verificar el estado del servicio
log "Verificando estado del servicio..."
systemctl status flask_app --no-pager

# Verificar que el servicio está realmente funcionando
sleep 10
if systemctl is-active --quiet flask_app; then
  log "✓ Servicio flask_app está ejecutándose correctamente"
else
  log "✗ ERROR: Servicio flask_app no está ejecutándose"
  log "Logs del servicio:"
  journalctl -u flask_app --no-pager -l | tail -20 | while read line; do log "$line"; done
fi

# Verificar que el puerto está abierto
if netstat -tuln | grep :8000 >/dev/null; then
  log "✓ Puerto 8000 está abierto y escuchando"
else
  log "✗ Warning: Puerto 8000 no parece estar abierto"
fi

log "Script de User Data completado"

# Log del estado final
log "=== Estado final del servicio ==="
systemctl status flask_app --no-pager | while read line; do log "$line"; done

# Marcar que el user data se completó
touch /home/ec2-user/user-data-completed
chown ec2-user:ec2-user /home/ec2-user/user-data-completed

log "User Data script finalizado exitosamente: $(date)"
