FROM python:3.12-slim

WORKDIR /app

COPY demos/GrocerySreDemo/src/prometheus_remote_write_proxy/server.py /app/server.py

ENV LISTEN_HOST=0.0.0.0 \
    LISTEN_PORT=8081

EXPOSE 8081

CMD ["python", "/app/server.py"]
