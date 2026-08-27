FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        rsyslog \
        rsyslog-relp \
        cron \
        logrotate \
    && rm -rf /var/lib/apt/lists/*

COPY rsyslog.conf /etc/rsyslog.conf
COPY logrotate.conf /etc/logrotate.d/rsyslog-json
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chmod 0644 /etc/logrotate.d/rsyslog-json

EXPOSE 514/udp 514/tcp 20514/tcp

ENTRYPOINT ["/entrypoint.sh"]
