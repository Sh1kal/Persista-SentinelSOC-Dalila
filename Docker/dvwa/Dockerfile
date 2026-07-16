FROM busybox:1.36.1-musl AS patch-tool

FROM vulnerables/web-dvwa AS patched-dvwa

COPY --from=patch-tool /bin/busybox /usr/local/bin/busybox
COPY login.php.patch /tmp/login.php.patch

RUN sed -i 's/\r$//' /var/www/html/login.php \
    && cd /var/www/html \
    && /usr/local/bin/busybox patch -p1 < /tmp/login.php.patch \
    && grep -q 'dvwa_auth_failure' /var/www/html/login.php \
    && php -l /var/www/html/login.php \
    && rm -f /tmp/login.php.patch /usr/local/bin/busybox

FROM vulnerables/web-dvwa

COPY --from=patched-dvwa --chown=www-data:www-data \
    /var/www/html/login.php /var/www/html/login.php

RUN grep -q 'dvwa_auth_failure' /var/www/html/login.php \
    && php -l /var/www/html/login.php \
    && mkdir -p /var/log/apache2 /var/log/dvwa \
    && touch /var/log/apache2/access.log \
             /var/log/apache2/error.log \
             /var/log/dvwa/auth.log \
    && chown root:adm /var/log/apache2/access.log /var/log/apache2/error.log \
    && chmod 0640 /var/log/apache2/access.log /var/log/apache2/error.log \
    && chown www-data:www-data /var/log/dvwa /var/log/dvwa/auth.log \
    && chmod 0750 /var/log/dvwa \
    && chmod 0640 /var/log/dvwa/auth.log

CMD ["apache2-foreground"]
