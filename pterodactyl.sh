#!/bin/bash

set -euf -o pipefail

export PTERODACTYL_PORT=${PTERODACTYL_PORT:-8066}

WINGS_BIN=/usr/local/bin/wings

cd "$(dirname "$0")"

detect_command() {
    command -v "$1" &>/dev/null
}

download_pterodactyl_panel() {
    echo "Downloading Pterodactyl Panel latest version..."
    local savefile
    savefile=$(mktemp)
    curl -L -o "$savefile" https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    pushd pterodactyl-panel
    tar -xzf "$savefile"
    popd
}

download_pterodactyl_wings() {
    echo "Downloading Pterodactyl Wings latest version..."
    curl -L -o $WINGS_BIN "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod +x $WINGS_BIN
}

init_pterodactyl_panel() {
    echo "Init Pterodactyl Panel config..."
    docker-compose exec app php artisan key:generate --force

    docker-compose exec app php artisan p:environment:setup \
        --new-salt \
        "--timezone=${PTERODACTYL_TIMEZONE:-Asia/Shanghai}" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=redis \
        --redis-pass= \
        --redis-port=6379 \
        --settings-ui=true

    docker-compose exec app php artisan p:environment:database \
        --host=db \
        --port=3306 \
        --database=pterodactyl \
        --username=pterodactyl \
        --password=pterodactyl
    
    docker-compose exec app php artisan migrate --seed --force

    echo
    echo "Create Pterodactyl Panel user"
    echo
    docker-compose exec app php artisan p:user:make
}

install_docker() {
    echo "Install Docker using https://get.docker.com"
    echo
    curl -fL https://get.docker.com | sh
}

install_docker_compose() {
    echo "Install Docker using linuxserver/docker-docker-compose"
    echo
    curl -fL https://raw.githubusercontent.com/linuxserver/docker-docker-compose/master/run.sh -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

install_pterodactyl_panel() {
    echo "Installing Pterodactyl Panel..."
    download_pterodactyl_panel
    if [[ ! -f pterodactyl-panel/.env ]]; then
        touch pterodactyl-panel/.init
        cp pterodactyl-panel/.env.example pterodactyl-panel/.env
    fi
    docker-compose pull
    docker-compose build --pull
    docker-compose up -d
    if [[ -f pterodactyl-panel/.init ]]; then
        init_pterodactyl_panel
        rm pterodactyl-panel/.init
        docker-compose stop
        docker-compose start
    fi
}

install_pterodactyl_wings() {
    echo "Installing Pterodactyl Wings..."
    [[ ! -d /etc/pterodactyl ]] && mkdir /etc/pterodactyl
    download_pterodactyl_wings
    sed "s|%WINGS_BIN%|$WINGS_BIN|" pterodactyl-wings.service.in | install -Dm664 /dev/stdin /etc/systemd/system/pterodactyl-wings.service
    systemctl daemon-reload
    systemctl enable --now pterodactyl-wings

}

install_main() {
    detect_command docker || install_docker
    detect_command docker-compose || install_docker_compose
    systemctl enable docker.service
    systemctl start docker.service
    docker info
    install_pterodactyl_panel
    install_pterodactyl_wings
    echo
    echo "Pterodactyl installed, Wings host: host.docker.internal, Visit it: http://127.0.0.1:${PTERODACTYL_PORT}"
}

uninstall_main() {
    local remove_data=0
    if [[ $# -ne 0 ]]; then
        case "$1" in
            --remove-data)
                remove_data=1
                shift
                ;;
        esac
    fi
    systemctl disable --now pterodactyl-wings
    rm /etc/systemd/system/pterodactyl-wings.service $WINGS_BIN
    systemctl daemon-reload
    if [[ $remove_data -eq 1 ]]; then
        docker-compose down --rmi all
        rm -r pterodactyl-panel
        rm -r pterodactyl-panel-database
        rm -r /etc/pterodactyl
    else
        docker-compose down
    fi
}

upgrade_main() {
    docker-compose pull
    docker-compose build --pull
    docker-compose down --rmi local

    download_pterodactyl_panel
    touch pterodactyl-panel/.upgrade
    docker-compose up -d
    docker-compose exec app php artisan view:clear
    docker-compose exec app php artisan config:clear
    docker-compose exec app php artisan migrate --seed --force
    rm pterodactyl-panel/.upgrade

    systemctl stop pterodactyl-wings
    download_pterodactyl_wings
    systemctl start pterodactyl-wings

    docker-compose stop
    docker-compose start
}

start_main() {
    docker-compose up -d
    systemctl start pterodactyl-wings
}

stop_main() {
    docker-compose down
    systemctl stop pterodactyl-wings
}

restart_main() {
    stop_main
    sleep 1
    start_main
}

usage() {
    cat <<EOL
Usage:  $(basename "$0") install                    # Install Pterodactyl
        $(basename "$0") uninstall [--remove-data]  # Uninstall Pterodactyl
                --remove-data: Delete all data
        $(basename "$0") upgrade                    # Upgrade Pterodactyl
        $(basename "$0") start                      # Start Pterodactyl
        $(basename "$0") stop                       # Stop Pterodactyl
        $(basename "$0") restart                    # Restart Pterodactyl
EOL
}

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root"
    exit 1
fi

if [[ $(systemd-detect-virt) == openvz ]]; then
    echo "The current system is virtualized as OpenVZ, does not support Docker, and cannot continue."
    exit 1
fi

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

for __dir in pterodactyl-panel pterodactyl-panel-database; do
    [[ ! -d $__dir ]] && mkdir $__dir
done
unset __dir

case "$1" in
    install)
        install_main "$@"
        ;;
    uninstall)
        uninstall_main "$@"
        ;;
    upgrade)
        upgrade_main "$@"
        ;;
    start)
        start_main "$@"
        ;;
    stop)
        stop_main "$@"
        ;;
    restart)
        restart_main "$@"
        ;;
    *)
        usage
        ;;
esac



