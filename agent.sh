#!/bin/bash

# Function to check service status
check_service() {
    service_name=$1
    if sudo systemctl is-active --quiet "$service_name"; then
        return 0
    else
        return 1
    fi
}

# Check and Install Python
which python3 &>/dev/null
if [ $? -ne 0 ]; then
    echo "Python3 not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y python3
else
    echo "Python3 is already installed!"
fi


# Check and Install Grafana
check_service grafana-server
if [ $? -ne 0 ]; then
    echo "Grafana not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
    sudo apt-get update
    sudo apt-get install -y grafana
    sudo systemctl start grafana-server
    sudo systemctl enable grafana-server
else
    echo "Grafana is already installed and active!"
fi

# Setup Loki configuration
wget https://raw.githubusercontent.com/grafana/loki/main/cmd/loki/loki-local-config.yaml

# Check and Install MinIO
which minio &>/dev/null
if [ $? -ne 0 ]; then
    echo "MinIO not found. Installing..."
    wget https://dl.min.io/server/minio/release/linux-amd64/minio
    chmod +x minio
    sudo mv minio /usr/local/bin/
    
    # Setting up MinIO as a service
    sudo useradd -r minio-user -s /sbin/nologin
    sudo mkdir /etc/minio
    sudo mkdir /var/minio
    sudo chown minio-user:minio-user /var/minio
    
    # Create default config
    echo 'MINIO_ACCESS_KEY="minio"
MINIO_SECRET_KEY="minio123"
MINIO_VOLUMES="/var/minio/"
MINIO_OPTS="--address :9000"' | sudo tee /etc/default/minio > /dev/null
    
    # Create systemd service file
    echo '[Unit]
Description=MinIO
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target
[Service]
User=minio-user
Group=minio-user
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/minio.service > /dev/null
    
    # Start and enable MinIO service
    sudo systemctl daemon-reload
    sudo systemctl enable minio
    sudo systemctl start minio
else
    echo "MinIO is already installed!"
fi

# Check and Install Loki (assuming binary installation for simplicity, you can adjust for your needs)
which loki &>/dev/null
if [ $? -ne 0 ]; then
    echo "Loki not found. Installing..."
    sudo apt-get update
    wget https://github.com/grafana/loki/releases/download/v2.4.1/loki-linux-amd64.zip
    unzip loki-linux-amd64.zip
    sudo mv loki-linux-amd64 /usr/local/bin/loki
    rm loki-linux-amd64.zip
    
    # Configure Loki to use MinIO (This is a simple example; adjust the configuration as per your requirements)
    echo 'auth_enabled: false
server:
  http_listen_port: 3100
ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  max_chunk_age: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s
  max_transfer_retries: 0
schema_config:
  configs:
  - from: 2020-05-15
    store: boltdb-shipper
    object_store: s3
    schema: v11
    index:
      prefix: index_
      period: 24h
storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/boltdb-cache
    cache_ttl: 24h
    shared_store: s3
  aws:
    s3: s3://minio:minio123@localhost:9000/loki/
    s3forcepathstyle: true
    endpoint: localhost:9000
    insecure: true
limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
chunk_store_config:
  max_look_back_period: 0s
table_manager:
  retention_deletes_enabled: false
  retention_period: 0s' | sudo tee /etc/loki/config.yml > /dev/null
    
    # Start Loki with the configuration
    sudo /usr/local/bin/loki -config.file=/etc/loki/config.yml &  # Consider setting up as a systemd service for production
else
    echo "Loki is already installed!"
fi
