#!/bin/bash
#
set -e

DOMAIN='socet.ir'
NGINX_UP_TIME=3

CERT_PATH="./certbot/conf/live/$DOMAIN/cert.pem"

# Function to check if the certificate is valid (not expired)
is_cert_valid() {
  local cert_file="$1"
  echo "Checking certificate: $cert_file"

  if [ ! -f "$cert_file" ]; then
    echo '❌ cert file does not exist'
    return 1
  fi

  if openssl x509 -in "$cert_file" -noout -checkend 0 > /dev/null; then
    echo "✅ cert is valid"
    return 0
  else
    echo "❌ cert is expired"
    return 1
  fi
}



apt update -y
#apt upgrade -y
apt install docker.io docker-compose -y

echo "=======add arvan docker registry======="
bash -c 'cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries" : ["https://docker.arvancloud.ir"],
  "registry-mirrors": ["https://docker.arvancloud.ir"]
}
EOF'

echo "=======logout and rerun docker to make effect of daemon.json======="
docker logout
systemctl restart docker

docker pull nginx
docker pull certbot/certbot

chown -R $(id -u):$(id -g) ./nginx
chown -R $(id -u):$(id -g) ./qbittorrent

echo "=======go to nginx======="
cd nginx

echo "=======replace the home.template with the http.template======="
sed "s/DOMAIN/$DOMAIN/g" http.template > templates/home.conf.template

echo "=======also replace the last docker-compose.yml with the correct domain name======="
sed -i "s/DOMAIN/$DOMAIN/g" docker-compose.yml

echo "=======donwload the needed stuff for certbot from the internet======="
mkdir -p ./certbot/conf
curl -o ./certbot/conf/options-ssl-nginx.conf https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf
curl -o ./certbot/conf/ssl-dhparams.pem https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem


echo "=======run docker-compose for nginx to run the service just for http======="
docker-compose up -d nginx

echo "=======wait for $NGINX_UP_TIME seconds so the nginx gets up======="
sleep $NGINX_UP_TIME

echo "=======check if SSL cert exists and is valid======="
if is_cert_valid "$CERT_PATH"; then
  echo "✅ SSL certificate already exists and is valid. Skipping certbot."
else
  echo "⚠️  SSL certificate is missing or expired. Running certbot..."
  docker-compose up certbot

  echo "=======waiting for certbot container to exit======="
  CERTBOT_EXIT_CODE=$(docker wait nginx_certbot_1)

  if [[ "$CERTBOT_EXIT_CODE" -ne 0 ]]; then
    echo "❌ Certbot container exited with code $CERTBOT_EXIT_CODE. Exiting the script."
    exit 1
  fi
fi

echo "=======replace the config with the full (including https) version======="
sed "s/DOMAIN/$DOMAIN/g" full.template > templates/home.conf.template

docker-compose down --remove-orphans
docker-compose up -d nginx

echo "=======go back======="
cd ..

echo "=======go to qbittorrent======="
cd qbittorrent

echo "=======run docker-compose for qbittorrent======="
docker-compose up -d

