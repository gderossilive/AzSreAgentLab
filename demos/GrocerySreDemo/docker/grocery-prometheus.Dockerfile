FROM prom/prometheus:v2.52.0

ARG API_FQDN
ARG WEB_FQDN

COPY demos/GrocerySreDemo/src/prometheus_monitoring/prometheus.yml.template /etc/prometheus/prometheus.yml.template

RUN /bin/sh -c 'set -euo pipefail; \
  test -n "$API_FQDN"; \
  test -n "$WEB_FQDN"; \
  sed -e "s/__API_FQDN__/${API_FQDN}/g" -e "s/__WEB_FQDN__/${WEB_FQDN}/g" /etc/prometheus/prometheus.yml.template > /etc/prometheus/prometheus.yml; \
  rm -f /etc/prometheus/prometheus.yml.template'

EXPOSE 9090
