#!/bin/bash
# user_data.sh
# Este script se ejecuta como root.

echo "Iniciando script de User Data para ${project_name}..."

# Actualizar el sistema e instalar dependencias básicas
yum update -y
yum -y install python3 mysql git aws-cli jq

# Instalar amazon-linux-extras si está disponible
if command -v amazon-linux-extras &> /dev/null; then
    amazon-linux-extras install epel -y
fi

# Instalar stress (opcional para testing)
yum -y install stress

# Configurar AWS CLI (asegúrate de que la instancia tenga un rol IAM con permisos adecuados)
aws configure set default.region ${aws_region}
aws configure set default.output json

# Clonar el repositorio de la aplicación PRIMERO
git clone https://github.com/ehoyos89/FlaskApp.git /home/ec2-user/flask-app

# Navegar al directorio de la aplicación
cd /home/ec2-user/flask-app

# Ahora instalar dependencias de Python desde requirements.txt
if [ -f "requirements.txt" ]; then
    pip3 install -r requirements.txt
else
    echo "Warning: requirements.txt no encontrado"
fi

# Instalar Gunicorn
pip3 install gunicorn

# Obtener secretos de AWS Secrets Manager usando AWS CLI
# Asegúrate de que el rol IAM de la instancia tenga permisos para Secrets Manager
echo "Obteniendo secretos de AWS Secrets Manager..."
DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id ${db_username_secret_arn} --query SecretString --output text | jq -r '.username')
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${db_password_secret_arn} --query SecretString --output text | jq -r '.password')
FLASK_SECRET=$(aws secretsmanager get-secret-value --secret-id ${flask_secret_key_secret_arn} --query SecretString --output text | jq -r '.secret_key')

# Crear directorio para variables de entorno
mkdir -p /etc/systemd/system/flask_app.service.d

# Configurar variables de entorno para la aplicación
cat > /etc/systemd/system/flask_app.service.d/environment.conf << EOF
[Service]
Environment="PHOTOS_BUCKET=${photos_bucket}"
Environment="DATABASE_HOST=${db_endpoint}"
Environment="DATABASE_USER=$DB_USERNAME"
Environment="DATABASE_PASSWORD=$DB_PASSWORD"
Environment="DATABASE_DB_NAME=${db_name}"
Environment="FLASK_SECRET_KEY=$FLASK_SECRET"
EOF

# También crear el archivo de perfil para depuración (opcional)
echo "export PHOTOS_BUCKET=\"${photos_bucket}\"" > /etc/profile.d/flask_app_env.sh
echo "export DATABASE_HOST=\"${db_endpoint}\"" >> /etc/profile.d/flask_app_env.sh
echo "export DATABASE_USER=\"$DB_USERNAME\"" >> /etc/profile.d/flask_app_env.sh
echo "export DATABASE_PASSWORD=\"$DB_PASSWORD\"" >> /etc/profile.d/flask_app_env.sh
echo "export DATABASE_DB_NAME=\"${db_name}\"" >> /etc/profile.d/flask_app_env.sh
echo "export FLASK_SECRET_KEY=\"$FLASK_SECRET\"" >> /etc/profile.d/flask_app_env.sh

# Dar permisos al usuario ec2-user para el directorio de la app
chown -R ec2-user:ec2-user /home/ec2-user/flask-app

# Crear un servicio systemd para Gunicorn (servidor WSGI para Flask)
cat > /etc/systemd/system/flask_app.service << EOF
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

# Recargar systemd y habilitar/iniciar el servicio
systemctl daemon-reload
systemctl enable flask_app

# Esperar un momento antes de iniciar el servicio
sleep 5
systemctl start flask_app

# Verificar el estado del servicio
systemctl status flask_app --no-pager

echo "Script de User Data finalizado."

# Log del estado final
echo "=== Estado final del servicio ===" >> /var/log/user-data.log
systemctl status flask_app --no-pager >> /var/log/user-data.log 2>&1