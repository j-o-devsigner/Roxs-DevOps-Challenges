# 1. Usar una imagen base oficial de Python
FROM python:3.9-slim

# 2. Establecer el directorio de trabajo dentro del contenedor
WORKDIR /app

# 3. Copiar el archivo de dependencias e instalarlas
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. Instalar curl para el healthcheck
RUN apt-get update && apt-get install -y curl

# 5. Copiar el resto del código de la aplicación
COPY . .

# 6. Exponer el puerto en el que la aplicación se ejecuta
EXPOSE 80

# 7. Comando para ejecutar la aplicación cuando el contenedor se inicie
CMD ["python3", "app.py"]
