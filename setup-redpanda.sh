#!/bin/bash
# Remove set -e to handle idempotent operations manually
# set -e

# Environment Variables with defaults
SUPER_USER="${REDPANDA_SUPERUSER_NAME:-superuser}"
SUPER_PASS="${REDPANDA_SUPERUSER_PASSWORD:-secretpassword}"
PRODUCER_USER="${PRODUCER_USER_NAME:-siscom-producer}"
PRODUCER_PASS="${PRODUCER_USER_PASSWORD:-producerpassword}"
CONSUMER_USER="${CONSUMER_USER_NAME:-siscom-consumer}"
CONSUMER_PASS="${CONSUMER_USER_PASSWORD:-consumerpassword}"
LIVE_CONSUMER_USER="${LIVE_CONSUMER_USER_NAME:-siscom-live-consumer}"
LIVE_CONSUMER_PASS="${LIVE_CONSUMER_USER_PASSWORD:-liveconsumerpassword}"
CONSUMER_TRIPS_USER="${CONSUMER_USER_TRIPS_NAME:-siscom-consumer-trips}"
CONSUMER_TRIPS_PASS="${CONSUMER_USER_TRIPS_PASSWORD:-consumertripspassword}"
GEOCONTEXT_USER="${CONSUMER_USER_GEOCONTEXT_NAME:-geocontext}"
GEOCONTEXT_PASS="${CONSUMER_USER_GEOCONTEXT_PASSWORD:-geocontext}"
EVENTS_PROCESSOR_USER="${CONSUMER_USER_EVENTS_PROCESSOR_NAME:-events-processor}"
EVENTS_PROCESSOR_PASS="${CONSUMER_USER_EVENTS_PROCESSOR_PASSWORD:-eventsprocessorpassword}"
EVENTS_PROCESSOR_PRODUCER_USER="${PRODUCER_USER_EVENTS_PROCESSOR_NAME:-events-processor-producer}"
EVENTS_PROCESSOR_PRODUCER_PASS="${PRODUCER_USER_EVENTS_PROCESSOR_PASSWORD:-eventsproducerpassword}"

# Helper function to wait for Redpanda Admin API
wait_for_admin() {
  echo "Waiting for Redpanda Admin API on 9644..."
  local count=0
  until curl -s http://redpanda:9644/v1/status/ready | grep "ready" > /dev/null 2>&1 || [ $count -eq 60 ]; do
    sleep 2
    count=$((count + 1))
  done
  if [ $count -eq 60 ]; then
    echo "Timeout waiting for Redpanda Admin API"
    curl -v http://redpanda:9644/v1/status/ready || true
    exit 1
  fi
}

# Helper function to wait for Redpanda Kafka API
wait_for_kafka() {
  local flags=$1
  echo "Waiting for Redpanda Kafka API on 9092..."
  local count=0
  until rpk cluster info --brokers redpanda:9092 $flags > /dev/null 2>&1 || [ $count -eq 60 ]; do
    sleep 2
    count=$((count + 1))
  done
  if [ $count -eq 60 ]; then
    echo "Timeout waiting for Redpanda Kafka API"
    exit 1
  fi
}

# Helper function to clear pid lock
clear_pid_lock() {
  if [ -f /var/lib/redpanda/data/pid.lock ]; then
    echo "Removing stale pid.lock..."
    rm -f /var/lib/redpanda/data/pid.lock
  fi
}

echo "[1/4] Starting Redpanda (Initial Setup)..."
clear_pid_lock
rpk redpanda start --overprovisioned --smp 1 --memory 1G --reserve-memory 0M --node-id "0" --check=false --kafka-addr PLAINTEXT://0.0.0.0:9092 --advertise-kafka-addr PLAINTEXT://localhost:9092 --set redpanda.core_balancing_continuous=false &
RP_PID=$!
wait_for_admin

echo "[2/4] Enabling SASL and Restarting..."
rpk cluster config set enable_sasl true || true
kill $RP_PID || true
sleep 5
clear_pid_lock

rpk redpanda start --overprovisioned --smp 1 --memory 1G --reserve-memory 0M --node-id 0 --check=false --kafka-addr SASL_PLAINTEXT://0.0.0.0:9092 --advertise-kafka-addr SASL_PLAINTEXT://redpanda:9092 &
RP_PID=$!
wait_for_admin

echo "[3/4] Creating Superuser and Configuring..."
rpk security user create "$SUPER_USER" -p "$SUPER_PASS" --mechanism SCRAM-SHA-256 --api-urls 127.0.0.1:9644 || echo "Superuser might already exist"
rpk cluster config set superusers "['$SUPER_USER']" -X admin.hosts=127.0.0.1:9644 || true
# Keep autobalancing mode on the non-Enterprise value to avoid license warnings.
rpk cluster config set partition_autobalancing_mode node_add -X admin.hosts=127.0.0.1:9644 || true

echo "[4/4] Creating App Users, Topics, and ACLs..."
rpk security user create "$PRODUCER_USER" -p "$PRODUCER_PASS" --mechanism SCRAM-SHA-256 || echo "Producer user already exists"
rpk security user create "$CONSUMER_USER" -p "$CONSUMER_PASS" --mechanism SCRAM-SHA-256 || echo "Consumer user already exists"
rpk security user create "$LIVE_CONSUMER_USER" -p "$LIVE_CONSUMER_PASS" --mechanism SCRAM-SHA-256 || echo "Live consumer user already exists"
rpk security user create "$CONSUMER_TRIPS_USER" -p "$CONSUMER_TRIPS_PASS" --mechanism SCRAM-SHA-256 || echo "Consumer trips user already exists"
rpk security user create "$GEOCONTEXT_USER" -p "$GEOCONTEXT_PASS" --mechanism SCRAM-SHA-256 || echo "Geocontext user already exists"
rpk security user create "$EVENTS_PROCESSOR_USER" -p "$EVENTS_PROCESSOR_PASS" --mechanism SCRAM-SHA-256 || echo "Events processor user already exists"
rpk security user create "$EVENTS_PROCESSOR_PRODUCER_USER" -p "$EVENTS_PROCESSOR_PRODUCER_PASS" --mechanism SCRAM-SHA-256 || echo "Events processor producer user already exists"

# Create topics individually and ignore "already exists" errors
for topic in siscom-messages siscom-minimal caudal-events caudal-live caudal-flows geocontext-enriched unit-events; do
  rpk topic create "$topic" \
    --brokers redpanda:9092 \
    -X sasl.mechanism=SCRAM-SHA-256 -X user="$SUPER_USER" -X pass="$SUPER_PASS" || echo "Topic $topic already exists"
done

# ACLs
rpk security acl create --allow-principal "User:$PRODUCER_USER" --operation write,describe --topic siscom-messages -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$PRODUCER_USER" --operation write,describe --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --topic siscom-messages -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --group 'siscom-consumer-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$LIVE_CONSUMER_USER" --operation read,describe --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$LIVE_CONSUMER_USER" --operation read,describe --group 'siscom-live-consumer-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_TRIPS_USER" --operation read,describe --topic siscom-messages -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_TRIPS_USER" --operation read,describe --group 'siscom-consumer-trips-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation read,describe --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation write,describe --topic geocontext-enriched -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation read,describe --topic geocontext-enriched -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation read,describe --group 'geocontext-enrichment-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_USER" --operation read,describe --group 'events-processor-group' --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_PRODUCER_USER" --operation write,describe --topic unit-events -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk cluster config set auto_create_topics_enabled false -X admin.hosts=127.0.0.1:9644 || true

echo "Redpanda setup finished successfully."

echo "Final Cluster Info:"
rpk cluster info \
  --brokers redpanda:9092 \
  -X sasl.mechanism=SCRAM-SHA-256 \
  -X user="$SUPER_USER" \
  -X pass="$SUPER_PASS"

wait $RP_PID
