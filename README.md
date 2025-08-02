# Introduction

This is a guide for deploying [Nextcloud](https://github.com/nextcloud/docker) behind a [Caddy](https://hub.docker.com/_/caddy) reverse proxy using docker compose. It is derived from ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1). It in part diverges from ```tmo1```'s guide in that this deployment uses the official image of [Caddy](https://hub.docker.com/_/caddy) rather than [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy), primarily in the interest of using the official image to avoid any dependency issues in the future.

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

This guide assumes you already have setup a domain name for your server. Consider seeing ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1#domain-name) for one solution.

# Install Docker

This guide assumes you have installed docker and docker-compose for your system. Consider following [this](https://wiki.archlinux.org/title/Docker) guide for Arch-based systems.

Consider that by default docker images are located in ```/var/lib/docker/```. You may consider moving the data root directory for docker if ```/var/lib/docker/``` doesn't have enough space for your Nextcloud data. You can configure the data root directory in ```/etc/docker/daemon.json```. See [this](https://wiki.archlinux.org/title/Docker#Images_location) for more information. For a fresh installation of docker, you may need to create the ```/etc/docker``` directory and ```/etc/docker/daemon.json``` file.

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
Consider also creating a second network to allow other apps to connect to Caddy. For example, I'm also running Nginx to host my web root: ```example.com```. Since Nginx doesn't need a static ip for the reverse proxy like Nextcloud, I opted to create a second network to benefit from docker's internal networking.

For example, you can create the ```caddy``` network by running:
```bash
docker network create \
        --driver=bridge \
        caddy
```

# Nextcloud

Create the Nextcloud docker compose file (```compose.yaml```) in the ```nextcloud``` project folder:

```bash
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
    # Select the Nextcloud version appropriate for your system
    # I used 30.0.13 due to a migration from bare metal to a docker container
    # So I needed both systems on the same version
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

# Caddy

