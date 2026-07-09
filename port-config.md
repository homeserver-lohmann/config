# Host Ports:

## OpenWebUI
3000 - OpenWebUI
3030 - SearXNG
3035 - Playwright Webloader
3060 - MCPO

## llama.cpp
8080 - llama-server
8090 - llama-proxy

## Minecraft
2000 - Crafty controller
25565 - Vanilla server
25566 - Middle Earth server


# Docker Internal Ports

## OpenWebUI
networks: [ OpenWebUI_net ]
8080 - OpenWebUI
8000 - MCPO
3030 - SearXNG
3035 - Playwright Websocket

## Crafty
8443 - Crafty controller