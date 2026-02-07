# Redpanda Container Setup

Este proyecto contiene la configuración necesaria para levantar un nodo de Redpanda dentro de un contenedor Docker, optimizado para desarrollo local y despliegue automático.

## Características

- Autenticación SASL/SCRAM habilitada por defecto.
- Creación explícita de tópicos durante el bootstrap (auto-create deshabilitado).
- Configuración de usuarios Admin (`superuser`) y usuarios de aplicación (`producer`/`consumer`).
- ACLs configuradas para restringir el acceso a los tópicos.
- Soporte para VS Code Dev Containers.
- Despliegue automático con GitHub Actions.

## Requisitos Previos

- Docker y Docker Compose instalados.
- Red y volumen externos creados.

## How to run locally

Ensure the network and volume exist:

```bash
docker network create siscom-network
docker volume create redpanda_data
```

Create your `.env` file from the example:

```bash
cp .env.example .env
```

(Optional) Edit `.env` to change default users and passwords.

Build and start:

```bash
docker-compose up -d --build
```

The setup runs automatically! You can monitor progress with:

```bash
docker logs -f redpanda-0
```

### 4. Comandos Útiles (RPK)

**Ver información del cluster:**

```bash
docker exec -it redpanda-0 rpk cluster info \
  -X user=superuser \
  -X pass=secretpassword \
  -X sasl.mechanism=SCRAM-SHA-256
```

**Listar tópicos:**

```bash
docker exec -it redpanda-0 rpk topic list \
  -X user=superuser \
  -X pass=secretpassword \
  -X sasl.mechanism=SCRAM-SHA-256
```

## 5. Agregar Usuarios, Tópicos y Permisos

### Crear un nuevo usuario

```bash
# Variables de ejemplo (cambiar según necesidad)
SUPERUSER=superuser
SUPERPASS=secretpassword
NEW_USER=nuevo-usuario
NEW_PASS=nueva-contraseña

docker exec -it redpanda-0 rpk security user create "$NEW_USER" \
  -p "$NEW_PASS" \
  --mechanism SCRAM-SHA-256 \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"
```

### Crear un nuevo tópico

```bash
# Variables de ejemplo
SUPERUSER=superuser
SUPERPASS=secretpassword
TOPIC_NAME=nuevo-topico

docker exec -it redpanda-0 rpk topic create "$TOPIC_NAME" \
  --brokers redpanda:9092 \
  -X sasl.mechanism=SCRAM-SHA-256 \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"
```

### Crear permisos (ACLs) para un usuario

#### Dar permisos de escritura en un tópico:

```bash
# Variables de ejemplo
SUPERUSER=superuser
SUPERPASS=secretpassword
APP_USER=nuevo-usuario
TOPIC_NAME=nuevo-topico

docker exec -it redpanda-0 rpk security acl create \
  --allow-principal "User:$APP_USER" \
  --operation write,describe \
  --topic "$TOPIC_NAME" \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"
```

#### Dar permisos de lectura en un tópico y grupo:

```bash
# Variables de ejemplo
SUPERUSER=superuser
SUPERPASS=secretpassword
APP_USER=nuevo-usuario
TOPIC_NAME=nuevo-topico
CONSUMER_GROUP=mi-grupo-consumidor

# Permisos en el tópico
docker exec -it redpanda-0 rpk security acl create \
  --allow-principal "User:$APP_USER" \
  --operation read,describe \
  --topic "$TOPIC_NAME" \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"

# Permisos en el grupo de consumo
docker exec -it redpanda-0 rpk security acl create \
  --allow-principal "User:$APP_USER" \
  --operation read,describe \
  --group "$CONSUMER_GROUP" \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"
```

### Listar usuarios:

```bash
docker exec -it redpanda-0 rpk security user list \
  -X user=superuser \
  -X pass=secretpassword
```

### Listar ACLs:

```bash
docker exec -it redpanda-0 rpk security acl list \
  -X user=superuser \
  -X pass=secretpassword
```

### Ejemplo completo: Agregar un nuevo consumidor

```bash
# 1. Definir variables
SUPERUSER=superuser
SUPERPASS=secretpassword
NEW_CONSUMER=app-consumer
NEW_CONSUMER_PASS=app-consumer-pass
TOPIC=app-events
CONSUMER_GROUP=app-consumer-group

# 2. Crear usuario
docker exec -it redpanda-0 rpk security user create "$NEW_CONSUMER" \
  -p "$NEW_CONSUMER_PASS" \
  --mechanism SCRAM-SHA-256 \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"

# 3. Dar permiso de lectura en el tópico
docker exec -it redpanda-0 rpk security acl create \
  --allow-principal "User:$NEW_CONSUMER" \
  --operation read,describe \
  --topic "$TOPIC" \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"

# 4. Dar permiso en el grupo de consumo
docker exec -it redpanda-0 rpk security acl create \
  --allow-principal "User:$NEW_CONSUMER" \
  --operation read,describe \
  --group "$CONSUMER_GROUP" \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"

# 5. Verificar que se creó correctamente
docker exec -it redpanda-0 rpk security user list \
  -X user="$SUPERUSER" \
  -X pass="$SUPERPASS"
```

**Nota:** Reemplaza las variables de ejemplo con tus propios valores. Para producción, utiliza variables de entorno desde un archivo `.env` seguro.
