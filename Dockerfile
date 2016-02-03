FROM mysql:5.6
MAINTAINER  Erik Osterman "e@osterman.com"

# System ENV
ENV TIMEZONE Etc/UTC
ENV DEBIAN_FRONTEND noninteractive
ENV PATH "$PATH:/usr/local/bin"
ENV TERM xterm
ENV PERL_MM_USE_DEFAULT true

RUN apt-get update && \
    apt-get -y install procps && \
    apt-get -y install libdbd-mysql libdbd-mysql-perl && \
    rm -f /var/log/mysql/error.log && \
    ln -s /dev/stderr /var/log/mysql/error.log

RUN chown -R mysql:mysql /var/lib/mysql/
ADD entrypoint.sh /entrypoint.sh
ADD my.cnf /etc/mysql/conf.d/
CMD mysqld_safe
