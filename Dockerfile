FROM debian:11

COPY entrypoint.sh /entrypoint.sh

RUN apt update
RUN apt -y upgrade
RUN apt -y install apt-transport-https lsb-release ca-certificates curl
RUN apt -y install cron supervisor
RUN curl -sSL https://packages.sury.org/php/README.txt | bash -x
RUN apt -y install php8.1-cli php8.1-gd php8.1-mysql php8.1-mbstring php8.1-bcmath php8.1-xml php8.1-fpm php8.1-curl php8.1-zip nginx
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
RUN ln -s /etc/init.d/php8.1-fpm /etc/init.d/php-fpm

COPY nginx.conf /etc/nginx/nginx.conf
COPY php.ini /etc/php/8.1/cli/conf.d/99-custom.ini
COPY php.ini /etc/php/8.1/fpm/conf.d/99-custom.ini
COPY php-fpm.conf /etc/php/8.1/fpm/php-fpm.conf
COPY supervisord.conf /etc/supervisor/supervisord.conf

RUN echo "* * * * * www-data php /pterodactyl-panel/artisan schedule:run" >> /etc/crontab
RUN nginx -t

VOLUME /pterodactyl-panel

WORKDIR /pterodactyl-panel

ENTRYPOINT ["bash", "/entrypoint.sh"]
