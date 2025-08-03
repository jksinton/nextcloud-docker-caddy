#!/bin/bash

docker network create \
	--driver=bridge \
	--subnet=172.16.0.0/16 \
	--gateway=172.16.0.1 \
	nc-proxy

docker network create \
	--driver=bridge \
	caddy
