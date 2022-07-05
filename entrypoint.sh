#!/bin/bash

composer install --no-dev --optimize-autoloader

chown -R www-data:www-data /pterodactyl-panel

[[ ! -f .init && ! -f .upgrade ]] && {
    /etc/init.d/cron start
    /etc/init.d/supervisor start
}

/etc/init.d/php-fpm start
/etc/init.d/nginx start

tail -f /var/log/nginx/nginx.log
# exec /usr/local/bin/apache2-foreground
