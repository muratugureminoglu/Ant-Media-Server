#!/bin/bash

CPU=$(grep -c 'processor' /proc/cpuinfo)
MEMORY=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
LOCAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)

DASHBOARD_URL="https://raw.githubusercontent.com/ant-media/Scripts/master/monitor/antmediaserver.json"
DATASOURCE_URL="https://raw.githubusercontent.com/ant-media/Scripts/master/monitor/datasource.json"

if [ "$MEMORY" -ge "7" ]; then
        sed -i '1s/^/-Xms4g\n-Xmx4g\n/' /etc/logstash/jvm.options
fi


sed -i "s/#.*pipeline.workers: 2/pipeline.workers: $CPU/g" /etc/logstash/logstash.yml
sed -i 's/num.partitions=1/num.partitions=4/g' /opt/kafka/config/server.properties

cat <<EOF >> /lib/systemd/system/kafka.service

[Unit]
Description=Apache Kafka Server
Requires=network.target remote-fs.target
After=network.target remote-fs.target kafka-zookeeper.service

[Service]
Type=simple
Environment=JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh

[Install]
WantedBy=multi-user.target

EOF

cat << EOF >> /lib/systemd/system/kafka-zookeeper.service

[Unit]
Description=Apache Zookeeper Server
Requires=network.target remote-fs.target
After=network.target remote-fs.target

[Service]
Type=simple
Environment=JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh

[Install]
WantedBy=multi-user.target

EOF

cat <<EOF >> /etc/logstash/conf.d/logstash.conf
input {
  kafka {
    bootstrap_servers => "127.0.0.1:9092"
    client_id => "logstash"
    group_id => "logstash"
    consumer_threads => 4
    topics => ["ams-instance-stats","ams-webrtc-stats","kafka-webrtc-tester-stats"]
    codec => "json"
    tags => ["log", "kafka_source"]
    type => "log"
  }
}

output {
  elasticsearch {
     hosts => ["127.0.0.1:9200"] 
     index => "logstash-%{[type]}-%{+YYYY.MM.dd}"
  }
}
EOF

cat <<EOF >> /opt/kafka/config/server.properties
advertised.listeners=INTERNAL_PLAINTEXT://$LOCAL_IP:9092,EXTERNAL_PLAINTEXT://$PUBLIC_IP:9093
listeners=INTERNAL_PLAINTEXT://0.0.0.0:9092,EXTERNAL_PLAINTEXT://0.0.0.0:9093
inter.broker.listener.name=INTERNAL_PLAINTEXT
listener.security.protocol.map=INTERNAL_PLAINTEXT:PLAINTEXT,EXTERNAL_PLAINTEXT:PLAINTEXT
EOF



wget -q $DASHBOARD_URL -O /tmp/antmediaserver.json
wget -q $DATASOURCE_URL -O /tmp/antmedia-datasource.json

curl "http://127.0.0.1:3000/api/dashboards/db" \
    -u "admin:admin" \
    -H "Content-Type: application/json" \
    --data-binary "@/tmp/antmediaserver.json"

curl "http://127.0.0.1:3000/api/datasource" \
    -u "admin:admin" \
    -H "Content-Type: application/json" \
  --data-binary "@/tmp/datasource.json"


systemctl restart kafka-zookeeper && systemctl restart kafka && systemctl restart logstash && systemctl restart grafana-server
