#!/bin/bash

CPU=$(grep -c 'processor' /proc/cpuinfo)
MEMORY=$(awk '/MemTotal/ {print int($2/1024/1024)}' /proc/meminfo)
LOCAL_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)

if [ "$MEMORY" -ge "7" ]; then
        sed -i '1s/^/-Xms4g\n-Xmx4g\n/' /etc/logstash/jvm.options
fi


sed -i "s/#.*pipeline.workers: 2/pipeline.workers: $CPU/g" /etc/logstash/logstash.yml
sed -i 's/num.partitions=1/num.partitions=4/g' /opt/kafka/config/server.properties

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

wget -q https://raw.githubusercontent.com/ant-media/Scripts/f5195aab1394f9f20bacf96746560c51e21d7c7d/monitor/antmediaserver.json -O /tmp/antmediaserver.json

curl "http://127.0.0.1:3000/api/dashboards/db" \
    -u "admin:admin" \
    -H "Content-Type: application/json" \
    --data-binary "@/tmp/antmediaserver.json"


systemctl restart kafka-zookeeper && systemctl restart kafka && systemctl restart logstash && systemctl restart grafana-server

