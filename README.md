# Introduction

This is a guide for deploying [Nextcloud](https://github.com/nextcloud/docker) behind a [Caddy](https://hub.docker.com/_/caddy) reverse proxy using docker compose. It is derived from ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1). It diverges from ```tmo1```'s guide in that this deployment uses the official image of [Caddy](https://hub.docker.com/_/caddy) rather than [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy), primarily in the interest of using the official image to avoid any dependency issues in the future.

# Domain Name

This guide assumes you already have setup a domain name for your server. Consider seeing ```tmo1```'s guide [here](https://gist.github.com/tmo1/72a9dc98b0b6b75f7e4ec336cdc399e1) for setuping a domain name.

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

# Create Docker Network

Configure at least one docker network outside of your compose files. This will be used to connect Caddy and the Nextcloud docker app. In your compose files, you will flag these networks as being ```external```, which tells docker compose not to manage the networks.

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
