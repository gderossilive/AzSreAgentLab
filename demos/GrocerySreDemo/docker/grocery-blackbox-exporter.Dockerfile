FROM prom/blackbox-exporter:v0.25.0

COPY demos/GrocerySreDemo/src/prometheus_monitoring/blackbox.yml /etc/blackbox_exporter/config.yml

EXPOSE 9115

ENTRYPOINT ["/bin/blackbox_exporter"]
CMD ["--config.file=/etc/blackbox_exporter/config.yml", "--web.listen-address=:9115"]
