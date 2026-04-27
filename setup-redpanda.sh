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
ALERT_USER_EVENTS_NAME="${CONSUMER_ALERT_USER_EVENTS_NAME:-events-alert-consumer}"
ALERT_USER_EVENTS_PASSWORD="${CONSUMER_ALERT_USER_EVENTS_PASSWORD:-eventsalertconsumerpassword}"
ALERT_RULES_PRODUCER_USER="${PRODUCER_ALERT_RULES_USER_NAME:-alerts-rules-producer}"
ALERT_RULES_PRODUCER_PASS="${PRODUCER_ALERT_RULES_USER_PASSWORD:-alertsrulesproducerpassword}"
ALERT_DISTRIBUTOR_USER="${ALERT_DISTRIBUTOR_USER_NAME:-alerts-distributor}"
ALERT_DISTRIBUTOR_PASS="${ALERT_DISTRIBUTOR_USER_PASSWORD:-alertsdistributorpassword}"
TELEMETRY_CONSOLIDATOR_USER="${TELEMETRY_CONSOLIDATOR_USER_NAME:-telemetry-consolidator}"
TELEMETRY_CONSOLIDATOR_PASS="${TELEMETRY_CONSOLIDATOR_USER_PASSWORD:-telemetryconsolidatorpassword}"

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
rpk redpanda start --overprovisioned --smp 1 --memory 1G --reserve-memory 0M --node-id "0" --check=false --kafka-addr PLAINTEXT://0.0.0.0:9092 --advertise-kafka-addr PLAINTEXT://localhost:9092 --set redpanda.core_balancing_continuous=false --set redpanda.partition_autobalancing_mode=off &
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
rpk cluster config set partition_autobalancing_mode off -X admin.hosts=127.0.0.1:9644 || true

echo "[4/4] Creating App Users, Topics, and ACLs..."
rpk security user create "$PRODUCER_USER" -p "$PRODUCER_PASS" --mechanism SCRAM-SHA-256 || echo "Producer user already exists"
rpk security user create "$CONSUMER_USER" -p "$CONSUMER_PASS" --mechanism SCRAM-SHA-256 || echo "Consumer user already exists"
rpk security user create "$LIVE_CONSUMER_USER" -p "$LIVE_CONSUMER_PASS" --mechanism SCRAM-SHA-256 || echo "Live consumer user already exists"
rpk security user create "$CONSUMER_TRIPS_USER" -p "$CONSUMER_TRIPS_PASS" --mechanism SCRAM-SHA-256 || echo "Consumer trips user already exists"
rpk security user create "$GEOCONTEXT_USER" -p "$GEOCONTEXT_PASS" --mechanism SCRAM-SHA-256 || echo "Geocontext user already exists"
rpk security user create "$EVENTS_PROCESSOR_USER" -p "$EVENTS_PROCESSOR_PASS" --mechanism SCRAM-SHA-256 || echo "Events processor user already exists"
rpk security user create "$EVENTS_PROCESSOR_PRODUCER_USER" -p "$EVENTS_PROCESSOR_PRODUCER_PASS" --mechanism SCRAM-SHA-256 || echo "Events processor producer user already exists"
rpk security user create "$ALERT_USER_EVENTS_NAME" -p "$ALERT_USER_EVENTS_PASSWORD" --mechanism SCRAM-SHA-256 || echo "Alert user events already exists"
# User for producing alert_rules changes on topic alert_rules_updates. Is used by the alert rules management API to send updates.
rpk security user create "$ALERT_RULES_PRODUCER_USER" -p "$ALERT_RULES_PRODUCER_PASS" --mechanism SCRAM-SHA-256 || echo "Alert rules producer user already exists"
# User for distributing the generated alerts to the different consumers. It needs read access to unit-alerts and write access to alert distribution topics (not created yet).
rpk security user create "$ALERT_DISTRIBUTOR_USER" -p "$ALERT_DISTRIBUTOR_PASS" --mechanism SCRAM-SHA-256 || echo "Alert distributor user already exists"
# User for consuming siscom-minimal and producing telemetry data to db. It needs read access to siscom-minimal 
rpk security user create "$TELEMETRY_CONSOLIDATOR_USER" -p "$TELEMETRY_CONSOLIDATOR_PASS" --mechanism SCRAM-SHA-256 || echo "Telemetry consolidator user already exists"
# Create topics individually and ignore "already exists" errors
for topic in siscom-messages siscom-minimal caudal-events caudal-live caudal-flows geocontext-enriched unit-events unit-alerts alert-rules-updates geofences-updates siscom-trusted; do
  rpk topic create "$topic" \
    --brokers redpanda:9092 \
    -X sasl.mechanism=SCRAM-SHA-256 -X user="$SUPER_USER" -X pass="$SUPER_PASS" || echo "Topic $topic already exists"
done

# ACLs
# SISCOM needs write access to siscom-messages and siscom-minimal, and read access to the same topics for the consumer. It also needs access to the consumer group to commit offsets.
rpk security acl create --allow-principal "User:$PRODUCER_USER" --operation write,describe --topic siscom-messages -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$PRODUCER_USER" --operation write,describe --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$PRODUCER_USER" --operation write,describe --topic siscom-trusted -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --topic siscom-messages -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --group 'siscom-consumer-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

# 
rpk security acl create --allow-principal "User:$LIVE_CONSUMER_USER" --operation read,describe --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$LIVE_CONSUMER_USER" --operation read,describe --topic unit-alerts -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$LIVE_CONSUMER_USER" --operation read,describe --group 'siscom-live-consumer-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true


# SISCOM CONSUMER TRIPS needs read access to siscom-messages and the consumer group to commit offsets.
rpk security acl create --allow-principal "User:$CONSUMER_TRIPS_USER" --operation read,describe --topic siscom-messages -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_TRIPS_USER" --operation read,describe --group 'siscom-consumer-trips-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation read,describe --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation write,describe --topic geocontext-enriched -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation read,describe --topic geocontext-enriched -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$GEOCONTEXT_USER" --operation read,describe --group 'geocontext-enrichment-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

# Events processor needs to consume from siscom-minimal and produce to unit-events, so it needs read access to the first and write access to the second. It also needs access to the consumer group to commit offsets.
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_USER" --operation read,describe --group 'events-processor-group' --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_USER" --operation read,describe --topic siscom-messages -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_USER" --operation read --group 'events-processor-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_USER" --operation read,describe --group 'events-processor-group' --topic geofences-update -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_USER" --operation read,describe --topic geofences-update -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$EVENTS_PROCESSOR_PRODUCER_USER" --operation write,describe --topic unit-events -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

# Alert processor needs to consume from siscom-minimal, produce to unit-alerts and read/write alert rules updates. It also needs access to the consumer groups to commit offsets.
rpk security acl create --allow-principal "User:$ALERT_USER_EVENTS_NAME" --operation read,describe --group 'alerts-producer-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$ALERT_USER_EVENTS_NAME" --operation write,describe --topic unit-alerts -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$ALERT_USER_EVENTS_NAME" --operation read,describe --group 'alert-processor-group' --topic unit-events -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$ALERT_USER_EVENTS_NAME" --operation read,describe --group 'alert-processor-group' --topic alert-rules-updates -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

# Alert distributor needs read access to unit-alerts 
rpk security acl create --allow-principal "User:$ALERT_DISTRIBUTOR_USER" --operation read,describe --topic unit-alerts -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$ALERT_DISTRIBUTOR_USER" --operation read,describe --group 'alert-distributor-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

# Telemetry consolidator needs read access to siscom-minimal and to its consumer group for committing offsets.
rpk security acl create --allow-principal "User:$TELEMETRY_CONSOLIDATOR_USER" --operation read,describe --topic siscom-minimal -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$TELEMETRY_CONSOLIDATOR_USER" --operation read,describe --group 'telemetry-consolidator-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

# Consumer to persist the events and alerts in the database needs read access to both unit-events and unit-alerts topics, and also to the consumer groups to commit offsets.
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --topic unit-events -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --group 'siscom-consumer-events-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --topic unit-alerts -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$CONSUMER_USER" --operation read,describe --group 'siscom-consumer-alerts-group' -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true

# Alert rules producer needs write access to alert-rules-updates topic to send the updates when rules are created/updated/deleted. USED EN SISCOM_ADMIN_API
rpk security acl create --allow-principal "User:$ALERT_RULES_PRODUCER_USER" --operation write,describe --topic alert-rules-updates -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$ALERT_RULES_PRODUCER_USER" --operation write,describe --topic user-devices-updates -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$ALERT_RULES_PRODUCER_USER" --operation write,describe --topic user-units-updates -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true
rpk security acl create --allow-principal "User:$ALERT_RULES_PRODUCER_USER" --operation write,describe --topic geofences-updates -X user="$SUPER_USER" -X pass="$SUPER_PASS" || true


# Disable auto topic creation to avoid mistakes. Topics should be created explicitly with the right configuration.
rpk cluster config set auto_create_topics_enabled false -X admin.hosts=127.0.0.1:9644 || true

echo "Redpanda setup finished successfully."

echo "Final Cluster Info:"
rpk cluster info \
  --brokers redpanda:9092 \
  -X sasl.mechanism=SCRAM-SHA-256 \
  -X user="$SUPER_USER" \
  -X pass="$SUPER_PASS"

wait $RP_PID
