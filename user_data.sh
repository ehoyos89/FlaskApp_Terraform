#!/bin/bash
# user_data.sh
# Este script se ejecuta como root.

echo "Iniciando script de User Data para ${project_name}..."

# Actualizar el sistema e instalar dependencias
yum update -y
yum -y install python3 mysql
pip3 install -r requirements.txt
amazon-linux-extras install epel
yum -y install stress

# Instalar y configurar AWS CLI
yum install -y aws-cli jq
# Configurar AWS CLI (asegúrate de que la instancia tenga un rol IAM con permisos adecuados)
aws configure set default.region ${aws_region}
aws configure set default.output json

# Instalar y configurar Git
yum install -y git
# Instalar y configurar Gunicorn
pip3 install gunicorn


# Clonar el repositorio de la aplicación
git clone https://github.com/ehoyos89/FlaskApp.git /home/ec2-user/flask-app

# Navegar al directorio de la aplicación
cd /home/ec2-user/flask-app

# Crear el archivo config.py (o configurarlo para usar variables de entorno)
# En este modelo, usaremos las variables de entorno para config.py
# NOTA: config.py busca en os.environ.
# Si tu config.py necesita cambiar, asegúrate de que lea estas variables.

# Obtener secretos de AWS Secrets Manager usando AWS CLI
# Asegúrate de que el rol IAM de la instancia tenga permisos para Secrets Manager
DB_USERNAME=$(aws secretsmanager get-secret-value --secret-id ${db_username_secret_arn} --query SecretString --output text | jq -r '.username')
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${db_password_secret_arn} --query SecretString --output text | jq -r '.password')
FLASK_SECRET=$(aws secretsmanager get-secret-value --secret-id ${flask_secret_key_secret_arn} --query SecretString --output text | jq -r '.secret_key')

# Configurar variables de entorno para la aplicación
echo "export PHOTOS_BUCKET=\"${photos_bucket}\"" >> /etc/profile.d/flask_app_env.sh
echo "export DATABASE_HOST=\"${db_endpoint}\"" >> /etc/profile.d/flask_app_env.sh
echo "export DATABASE_USER=\"${DB_USERNAME}\"" >> /etc/profile.d/flask_app_env.sh
echo "export DATABASE_PASSWORD=\"${DB_PASSWORD}\"" >> /etc/profile.d/flask_app_env.sh
echo "export DATABASE_DB_NAME=\"${db_name}\"" >> /etc/profile.d/flask_app_env.sh
echo "export FLASK_SECRET=\"${FLASK_SECRET}\"" >> /etc/profile.d/flask_app_env.sh

# Dar permisos al usuario ec2-user para el directorio de la app
chown -R ec2-user:ec2-user /home/ec2-user/flask-app

# Crear un servicio systemd para Gunicorn (servidor WSGI para Flask)
# Esto asegura que tu aplicación se inicie automáticamente y se reinicie en caso de falla.
cat <<EOF > /etc/systemd/system/flask_app.service
[Unit]
Description=Gunicorn instance to serve flask_app
After=network.target

[Service]
User=ec2-user
Group=ec2-user
WorkingDirectory=/home/ec2-user/flask-app
EnvironmentFile=/etc/profile.d/flask_app_env.sh
ExecStart=/usr/bin/python3 -m gunicorn --workers 4 --bind 0.0.0.0:8000 application:application # Asegúrate que application.py se llama así y la app se llama 'application'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y habilitar/iniciar el servicio
systemctl daemon-reload
systemctl enable flask_app
systemctl start flask_app

echo "Script de User Data finalizado."