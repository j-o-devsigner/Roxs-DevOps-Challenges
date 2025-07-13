# 1. Usar una imagen base oficial de Node.js
FROM node:18-alpine

# 2. Establecer el directorio de trabajo
WORKDIR /app

# 3. Copiar los archivos de dependencias e instalarlas
COPY package*.json ./
RUN npm install

# 4. Instalar curl para el healthcheck
RUN apk update && apk add --no-cache curl

# 5. Copiar el resto del código del worker
COPY . .

# 6. Comando para ejecutar el worker
CMD ["npm", "start"]
