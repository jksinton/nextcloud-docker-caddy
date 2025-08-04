# Introduction

This is an example of a [Nextcloud](https://github.com/nextcloud/docker) docker image served behind a reverse proxying, using a [Caddy](https://hub.docker.com/_/caddy) docker image. In this example, the Nextcloud app serves a subdomain ```cloud.exmaple.com``` of the web root domain ```example.com```. Allowing you to easily spin-up other docker containers under your domain's web root and other subdomains.

First off, thank you, [```tmo1```](https://gist.github.com/tmo1). This deployment is primarily derived from ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1). It in part diverges from ```tmo1```'s configuration in that this deployment uses the official image of [Caddy](https://hub.docker.com/_/caddy) rather than [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy).

# Docker Compose Project Structure

This deploment uses the following project structure:

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
where ```stacks``` represents the root of your docker stack projects. You can consider working on this deployment under ```stack``` in ```$HOME``` or alternatively, ```/opt```. 

# Domain Name

This guide assumes you already have setup a domain name for your server. Consider seeing ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1#domain-name) for one solution. In addition, a subdomain (for example, ```cloud.example.com```) is setup for your Nextcloud app.

# Install Docker

This guide assumes you have installed docker and docker-compose on your system. Consider using [this](https://wiki.archlinux.org/title/Docker) wiki article on how to install and intially ocnfigure docker for Arch-based systems.

## Docker's Data Root
Consider that by default docker images are located in ```/var/lib/docker/```. You may consider moving the data root directory for docker if ```/var/lib/docker/``` doesn't have enough space for your Nextcloud data. You can configure the data root directory in ```/etc/docker/daemon.json```. See [this](https://wiki.archlinux.org/title/Docker#Images_location) for more information. For a fresh installation of docker, you may need to create the ```/etc/docker``` directory and ```/etc/docker/daemon.json``` file.

## Docker user group
This guide also assumes the user running the command is part of the ```docker``` user group or is being run by root (for example, via ```sudo```).

# Create a Docker Network

Create a docker network outside of your compose files. This will be used to connect Caddy to the Nextcloud docker app. In your compose files, you will flag the docker networks as being ```external```, which tells docker compose to NOT manage the networks [See, for example](https://docs.docker.com/compose/how-tos/networking/#use-an-existing-network).

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
Consider creating a second network to allow other apps to connect to Caddy. For example, I'm also running an Nginx docker image to host the web root: ```example.com```. Since Nginx doesn't need a static ip for the reverse proxy like Nextcloud, you can create a second network to benefit from docker's internal [networking](https://docs.docker.com/reference/compose-file/networks/).

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

## Congigure Nextcloud's cron

Configure cron. See https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/background_jobs_configuration.html

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
TZ='America/Chicago'
```
TODO: Confirm whether these environment variables are still necessary.

Start Caddy by running this in the ```caddy``` project folder:
```bash
docker compose up -d
```

For debugging, consider running the container in the foreground:
```bash
docker compose up
```

# Hosting Web Root

If you want to host the web root of your domain, for example, [a linktree](https://github.com/vitor-antoni/linktree-template) using Nginx, create another docker compose project:

```
www
├── build-nginx
│   ├── Dockerfile
│   └── html
│       └── index.html
└── compose.yaml
```
```www``` can be inside the stacks docker projects folder.

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
You will need to copy the html data and update the ownership using [```chown```](https://hub.docker.com/_/nginx#user-and-group-id).

Put your static HTML (for example, ```index.html```) in the ```html``` folder, which is in the ```build-nginx``` folder. For example, you can make the root [a linktree](https://github.com/vitor-antoni/linktree-template). As an alternative, you can make this a wordpress app or the like. 

Start Nginx by running this in the ```www``` project folder:
```bash
docker compose up -d
```
