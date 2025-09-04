# RabbitMQ MQTT Testing Guide

Complete configuration and testing information for RabbitMQ with MQTT support.

## 📋 MQTT Configuration Summary

### ✅ Confirmed Working Configuration

| Component | Status | Details |
|-----------|--------|---------|
| **Container** | ✅ Running | `rabbitmq:3-management` |
| **MQTT Plugin** | ✅ Enabled | `rabbitmq_mqtt`, `rabbitmq_web_mqtt` |
| **MQTT Port** | ✅ Exposed | `1883` (non-TLS) |
| **WebSocket MQTT** | ✅ Exposed | `15675` |
| **TLS MQTT** | ⚠️ Disabled | `8883` (available but not enabled) |
| **Authentication** | ✅ Working | `admin/password` |

## 🔌 Port Configuration

```
Port Mappings (Verified):
├── 1883/tcp -> 0.0.0.0:1883     # MQTT Protocol
├── 5672/tcp -> 0.0.0.0:5672     # AMQP Protocol  
├── 15672/tcp -> 0.0.0.0:15672   # Management UI
└── 15675/tcp -> 0.0.0.0:15675   # MQTT over WebSockets
```

## 🧪 MQTT Test Configuration

### Connection Details
```yaml
Host: localhost
Port: 1883
Protocol: MQTT 3.1.1 / 5.0
Security: None (non-TLS)
Username: admin
Password: password
```

### Remote Access (from Windows Host)
```yaml
Host: 172.23.4.238  # Your WSL IP
Port: 1883
Username: admin
Password: password
```

## 🚀 Quick Test Commands

### Basic Publish/Subscribe Test

**Terminal 1 (Subscriber):**
```bash
mosquitto_sub -h localhost -p 1883 -u admin -P password -t test/topic
```

**Terminal 2 (Publisher):**
```bash
mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/topic -m "Hello MQTT World!"
```

### Advanced Testing Examples

#### Sensor Data Simulation
```bash
# Temperature sensor
mosquitto_pub -h localhost -p 1883 -u admin -P password -t sensors/temperature -m "22.5"

# Humidity sensor  
mosquitto_pub -h localhost -p 1883 -u admin -P password -t sensors/humidity -m "65.2"

# Subscribe to all sensors
mosquitto_sub -h localhost -p 1883 -u admin -P password -t sensors/+
```

#### QoS Testing
```bash
# QoS Level 0 (At most once)
mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/qos0 -m "QoS 0 Message" -q 0

# QoS Level 1 (At least once)
mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/qos1 -m "QoS 1 Message" -q 1

# QoS Level 2 (Exactly once)
mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/qos2 -m "QoS 2 Message" -q 2
```

#### Retained Messages
```bash
# Publish retained message
mosquitto_pub -h localhost -p 1883 -u admin -P password -t status/server -m "online" -r

# New subscribers will immediately receive the retained message
mosquitto_sub -h localhost -p 1883 -u admin -P password -t status/server
```

#### Wildcard Subscriptions
```bash
# Single level wildcard (+)
mosquitto_sub -h localhost -p 1883 -u admin -P password -t sensors/+/temperature

# Multi-level wildcard (#)
mosquitto_sub -h localhost -p 1883 -u admin -P password -t sensors/#

# All topics
mosquitto_sub -h localhost -p 1883 -u admin -P password -t "#"
```

## 🌐 WebSocket MQTT Testing

### Connection Details
```yaml
WebSocket URL: ws://localhost:15675/ws
Username: admin
Password: password
```

### JavaScript Example
```javascript
// Using Paho MQTT JavaScript client
const client = new Paho.MQTT.Client("localhost", 15675, "/ws", "client_" + Math.random());

client.onConnectionLost = function(responseObject) {
    console.log("Connection lost: " + responseObject.errorMessage);
};

client.onMessageArrived = function(message) {
    console.log("Message arrived: " + message.payloadString);
};

// Connect
client.connect({
    userName: "admin",
    password: "password",
    onSuccess: function() {
        console.log("Connected to RabbitMQ MQTT via WebSocket");
        client.subscribe("test/websocket");
        
        // Publish a message
        const message = new Paho.MQTT.Message("Hello from WebSocket!");
        message.destinationName = "test/websocket";
        client.send(message);
    },
    onFailure: function(error) {
        console.log("Connection failed: " + error.errorMessage);
    }
});
```

## 🛠️ Script-Based Testing

### Automated Tests
```bash
# Run comprehensive MQTT connectivity test
./install_rabbitmq_docker.sh mqtt-test

# Check detailed MQTT status and examples
./install_rabbitmq_docker.sh mqtt-status

# Overall system status
./install_rabbitmq_docker.sh status
```

### Manual Script Management
```bash
# Start RabbitMQ
./install_rabbitmq_docker.sh start

# Stop RabbitMQ
./install_rabbitmq_docker.sh stop

# Restart RabbitMQ
./install_rabbitmq_docker.sh restart

# View logs
./install_rabbitmq_docker.sh logs

# Enable MQTT plugins (if needed)
./install_rabbitmq_docker.sh mqtt-enable
```

## 🔧 Advanced Configuration

### Enable TLS MQTT (Port 8883)

1. **Edit the script configuration:**
   ```bash
   # In install_rabbitmq_docker.sh, change:
   ENABLE_MQTT_TLS="true"
   ```

2. **Recreate container:**
   ```bash
   ./install_rabbitmq_docker.sh remove
   ./install_rabbitmq_docker.sh install
   ```

3. **Test TLS connection:**
   ```bash
   mosquitto_pub -h localhost -p 8883 -u admin -P password -t test/tls -m "Secure message" --cafile ca.crt
   ```

### Custom MQTT Configuration

To modify MQTT settings, you can access the RabbitMQ container:

```bash
# Enter container
docker exec -it rabbitmq bash

# Edit MQTT configuration
# /etc/rabbitmq/rabbitmq.conf
```

## 📊 Monitoring and Management

### Management UI Access
- **URL**: http://localhost:15672
- **Username**: admin
- **Password**: password
- **MQTT Section**: Admin → Connections (shows MQTT clients)

### View MQTT Connections
```bash
# List active MQTT connections
docker exec rabbitmq rabbitmqctl list_connections

# View MQTT plugin status
docker exec rabbitmq rabbitmq-plugins list | grep mqtt
```

### Log Analysis
```bash
# Real-time logs
./install_rabbitmq_docker.sh logs

# MQTT-specific log filtering
docker logs rabbitmq 2>&1 | grep -i mqtt
```

## 🧪 Performance Testing

### High-Volume Testing
```bash
# Publish 1000 messages rapidly
for i in {1..1000}; do
    mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/performance -m "Message $i"
done

# Subscribe with message count limit
mosquitto_sub -h localhost -p 1883 -u admin -P password -t test/performance -C 1000
```

### Connection Stress Test
```bash
# Multiple concurrent subscribers
for i in {1..10}; do
    mosquitto_sub -h localhost -p 1883 -u admin -P password -t test/stress$i &
done

# Multiple concurrent publishers
for i in {1..10}; do
    mosquitto_pub -h localhost -p 1883 -u admin -P password -t test/stress$i -m "Stress test $i" &
done
```

## 🔍 Troubleshooting

### Common Issues and Solutions

#### Connection Refused
```bash
# Check if container is running
docker ps | grep rabbitmq

# Check port exposure
docker port rabbitmq

# Restart if needed
./install_rabbitmq_docker.sh restart
```

#### MQTT Plugin Not Working
```bash
# Check plugin status
./install_rabbitmq_docker.sh mqtt-status

# Enable plugins manually
./install_rabbitmq_docker.sh mqtt-enable

# Check logs for errors
./install_rabbitmq_docker.sh logs | grep -i error
```

#### Authentication Issues
```bash
# Verify credentials in Management UI
# http://localhost:15672 → Admin → Users

# Test with different credentials
mosquitto_pub -h localhost -p 1883 -u guest -P guest -t test/auth -m "test"
```

### Diagnostic Commands
```bash
# Test basic connectivity
nc -zv localhost 1883

# Check if MQTT port is listening
netstat -tuln | grep 1883

# Verify mosquitto-clients installation
which mosquitto_pub mosquitto_sub

# Test without authentication (if allowed)
mosquitto_pub -h localhost -p 1883 -t test/noauth -m "test"
```

## 📈 Integration Examples

### Python MQTT Client
```python
import paho.mqtt.client as mqtt

def on_connect(client, userdata, flags, rc):
    print(f"Connected with result code {rc}")
    client.subscribe("test/python")

def on_message(client, userdata, msg):
    print(f"Received: {msg.topic} {msg.payload.decode()}")

client = mqtt.Client()
client.username_pw_set("admin", "password")
client.on_connect = on_connect
client.on_message = on_message

client.connect("localhost", 1883, 60)
client.loop_forever()
```

### Node.js MQTT Client
```javascript
const mqtt = require('mqtt');

const client = mqtt.connect('mqtt://localhost:1883', {
    username: 'admin',
    password: 'password'
});

client.on('connect', () => {
    console.log('Connected to RabbitMQ MQTT');
    client.subscribe('test/nodejs');
    client.publish('test/nodejs', 'Hello from Node.js!');
});

client.on('message', (topic, message) => {
    console.log(`Received: ${topic} - ${message.toString()}`);
});
```

## ✅ Test Checklist

- [ ] Basic publish/subscribe test
- [ ] Authentication verification
- [ ] QoS level testing (0, 1, 2)
- [ ] Retained message testing
- [ ] Wildcard subscription testing
- [ ] WebSocket MQTT testing
- [ ] Remote access testing (from Windows)
- [ ] Performance testing
- [ ] Management UI verification
- [ ] Plugin status confirmation

## 📝 Notes

- **Container**: `rabbitmq` (Docker container name)
- **Image**: `rabbitmq:3-management`
- **Data Persistence**: `/var/lib/rabbitmq` (Docker volume: `rabbitmq_data`)
- **Configuration**: Default RabbitMQ configuration with MQTT plugins
- **Security**: Basic authentication (admin/password)
- **Last Tested**: September 4, 2025
- **Test Status**: ✅ All core functionality verified working

---

**Generated by**: RabbitMQ MQTT Installation Script  
**Script Location**: `./install_rabbitmq_docker.sh`  
**Documentation Updated**: September 4, 2025
