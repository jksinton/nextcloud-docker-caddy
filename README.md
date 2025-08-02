# Introduction

This is a guide for deploying [Nextcloud](https://github.com/nextcloud/docker) behind a [Caddy](https://hub.docker.com/_/caddy) reverse proxy using docker compose, where the Nextcloud app serves a subdomain ```cloud.exmaple.com```. It is derived from ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1). It in part diverges from ```tmo1```'s guide in that this deployment uses the official image of [Caddy](https://hub.docker.com/_/caddy) rather than [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy), primarily in the interest of using the official image to avoid any dependency issues in the future.

# Docker Compose Project Structure

The docker compose projects will have this structure:

```md
stacks
├── caddy
│   ├── caddy-build
│   │   ├── Caddyfile
│   │   └── Dockerfile
│   ├── caddy-env
│   │   └── .env
│   └── compose.yaml
├── networks
│   ├── mk-networks.sh
│   └── rm-network.sh
└── nextcloud
    └── compose.yaml
    └── .env
```

# Domain Name

This guide assumes you already have setup a domain name for your server. Consider seeing ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1#domain-name) for one solution. In addition, a subdomain (for example, ```cloud.example.com```) is setup for your Nextcloud app.

# Install Docker

This guide assumes you have installed docker and docker-compose for your system. Consider following [this](https://wiki.archlinux.org/title/Docker) guide for Arch-based systems.

Consider that by default docker images are located in ```/var/lib/docker/```. You may consider moving the data root directory for docker if ```/var/lib/docker/``` doesn't have enough space for your Nextcloud data. You can configure the data root directory in ```/etc/docker/daemon.json```. See [this](https://wiki.archlinux.org/title/Docker#Images_location) for more information. For a fresh installation of docker, you may need to create the ```/etc/docker``` directory and ```/etc/docker/daemon.json``` file.

This guide also assumes the user running the command is part of the ```docker``` user group or is being run by root (for example, via ```sudo```).

# Create a Docker Network

Create a docker network outside of your compose files. This will be used to connect Caddy and the Nextcloud docker app. In your compose files, you will flag these networks as being ```external```, which tells docker compose not to manage the networks.

Run ```mk-networks.sh```:
```bash
# ./mk-networks.sh
```
or 
```bash
docker network create \
        --driver=bridge \
        --subnet=172.16.0.0/16 \
        --gateway=172.16.0.1 \
        nc-proxy
```
Consider creating a second network to allow other apps to connect to Caddy. For example, I'm also running Nginx to host my web root: ```example.com```. Since Nginx doesn't need a static ip for the reverse proxy like Nextcloud, I opted to create a second network to benefit from docker's internal networking.

For example, you can create the ```caddy``` network by running:
```bash
docker network create \
        --driver=bridge \
        caddy
```

# Nextcloud

Create the docker compose file (```compose.yaml```) for Nextcloud in the ```nextcloud``` project folder:

```yaml
# See https://github.com/nextcloud/docker/?tab=readme-ov-file#running-this-image-with-docker-compose

services:
  db:
    # Note: Check the recommend version here: https://docs.nextcloud.com/server/latest/admin_manual/installation/system_requirements.html#server
    image: mariadb:lts
    restart: always
    command: --transaction-isolation=READ-COMMITTED
    volumes:
      - db:/var/lib/mariadb
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
    networks:
      - backend

  # Note: Redis is an external service. You can find more information about the configuration here:
  # https://hub.docker.com/_/redis
  redis:
    image: redis:alpine
    restart: always
    networks:
      - backend
  
  # Nextcloud apache container config:
  nc-app:
    # Select the Nextcloud image version appropriate for your system
    # I used 30.0.13 due to a migration from bare metal to a docker container
    # Thus, I needed both systems (old-bare metal and new-docker) to be on the same version.
    image: nextcloud:30.0.13-apache
    restart: always
    # Enable ports for testing
    # ports:
    #  - 8080:80
    depends_on:
      - redis
      - db
    volumes:
      - nextcloud:/var/www/html
      - config:/var/www/html/config
      - data:/var/www/html/data
    environment:
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_HOST=db
      # See https://github.com/nextcloud/docker/?tab=readme-ov-file#using-the-image-behind-a-reverse-proxy-and-specifying-the-server-host-and-protocol
      # See also https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html
      - TRUSTED_PROXIES=172.16.0.2
      - APACHE_DISABLE_REWRITE_IP=1
    networks:
      backend:
      nc-proxy:
        # static ip to allow TRUSTED_PROXIES to be set above
        ipv4_address: 172.16.0.3

volumes:
  nextcloud:
  config:
  data:
  db:

networks:
  backend: 
  nc-proxy:
    external: true
```

Set the mysql passwords in the ```.env``` file:
```bash
MYSQL_ROOT_PASSWORD=password1
MYSQL_PASSWORD=password2
```
Update the permissions of ```.env```:
```bash
chmod 600 .env
```
Start Nextcloud by running this in the ```nextcloud``` project folder:
```bash
docker compose up -d
```

For debugging, consider running the container in the foreground:
```bash
docker compose up
```

If you have access to the host of the Nextcloud app, consider uncommenting the ports section. You can bring up the Nextcloud app, and configure the installation at [localhost:8080](http://localhost:8080/) before exposing the image to the world wide web.  You can also do this step just to verify that you can see the initial install screen.

# Caddy

Create the docker compose file (```compose.yaml```) for Caddy in your ```caddy``` project folder:
```yaml
services:
  caddy:
    build: ./caddy-build/.
    restart: always
    ports:
      - "80:80"
      - "443:443"
    env_file:
      - ./caddy-env/.env
    volumes:
      - ./caddy-build/Caddyfile:/etc/caddy/Caddyfile
    networks:
      nc-proxy:
        ipv4_address: 172.16.0.2
      caddy:

networks:
  nc-proxy:
    external: true
  caddy:
    external: true
```
Note this includes the second docker network ```caddy``` to connect to an Nginx app for the web root. You can remove this network, if you aren't using a similar configuration.

Create the ```Dockerfile``` in the ```caddy-build``` folder:
```bash
FROM caddy:latest
COPY Caddyfile /etc/caddy/Caddyfile
```
Create the ```Caddyfile``` in the ```caddy-build``` folder:
```
{
    email {$ACME_EMAIL}
}

# nginx web-root
example.com {
    reverse_proxy nginx-app:80
}

# Nextcloud
cloud.example.com {
    reverse_proxy nc-app:80
}
```
Create the ```.env``` file in the ```caddy-env``` folder:
```bash
ACME_EMAIL="email@example.com"
ACME_AGREE=true
TZ='America/Chicago'
```
Update your email and timezone to the appropriate values.

Start Caddy by running this in the ```caddy``` project folder:
```bash
docker compose up -d
```

For debugging, consider running the container in the foreground:
```bash
docker compose up
```

# Hosting Web Root

If you want to host the web root of your domain, for example, a linktree using Nginx, create another docker compose project:

```
www
├── build-nginx
│   ├── Dockerfile
│   └── html
│       └── index.html
└── compose.yaml
```
Create the docker compose file (```compose.yaml```) for Nginx in your ```www``` project folder:
```yaml
services:
  nginx-app:
    build: ./build-nginx/.
    restart: always
    # ports:
    #  - 8080:80
    networks:
      - caddy

networks:
  caddy:
    external: true
```
Create the ```Dockerfile``` in the ```build-nginx``` folder:
```bash
FROM nginx
COPY --chown=101:101 ./html /usr/share/nginx/html
```

Start Nginx by running this in the ```www``` project folder:
```bash
docker compose up -d
```
