#!/usr/bin/env bash
# hace que el script termine si algún comando falla
set -e

# Parámetros

if [ "$#" -ne 3 ]; then
  echo "Uso: $0 <repo_url> <runner_token> <runner_label>"
  exit 1
fi

REPO_URL=$1
RUNNER_TOKEN=$2
RUNNER_LABEL=$3
RUNNER_USER="vagrant" # Usuario que ejecutará el servicio
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

echo "### Configurando runner para repo: $REPO_URL con etiqueta: $RUNNER_LABEL ###"

# 1. Instalar dependencias
sudo apt-get update
sudo apt-get install -y curl jq

# 2. Instalar Docker si no existe
if ! command -v docker >/dev/null 2>&1; then
  echo "Instalando Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  # Aseguramos que el usuario vagrant pueda usar Docker sin sudo dentro de la VM
  sudo usermod -aG docker $RUNNER_USER 
  rm get-docker.sh
fi

# 3. Crear directorio como el usuario vagrant
#    Usamos su -c para ejecutar comandos como otro usuario
sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# 4. Descargar y descomprimir el runner
LATEST_VERSION=$(curl -s -X GET 'https://api.github.com/repos/actions/runner/releases/latest' | jq -r '.tag_name' | sed 's/v//')
RUNNER_TAR_FILE="actions-runner-linux-x64-${LATEST_VERSION}.tar.gz"

if [ ! -f "${RUNNER_TAR_FILE}" ]; then
    echo "Descargando la última versión del runner: ${LATEST_VERSION}"
    curl -o "${RUNNER_TAR_FILE}" -L "https://github.com/actions/runner/releases/download/v${LATEST_VERSION}/${RUNNER_TAR_FILE}"
    tar xzf "./${RUNNER_TAR_FILE}"
    rm "./${RUNNER_TAR_FILE}"
    # Aseguramos que los archivos pertenezcan al usuario correcto
    sudo chown -R $RUNNER_USER:$RUNNER_USER "$RUNNER_DIR"
fi

# 5. Ejecutar la configuración del runner COMO EL USUARIO 'vagrant'
echo "Configurando runner como usuario ${RUNNER_USER}..."
sudo -u "$RUNNER_USER" ./config.sh --unattended --url "${REPO_URL}" --token "${RUNNER_TOKEN}" --name "$(hostname)" --labels "${RUNNER_LABEL}" --replace

# 6. Instalar y iniciar el servicio del runner
echo "Instalando y arrancando el servicio del runner..."
sudo ./svc.sh install "$RUNNER_USER"
sudo ./svc.sh start

echo "### Runner configurado y corriendo como un servicio. ###"
