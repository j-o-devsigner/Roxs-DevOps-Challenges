# 1. Usar una imagen base oficial de Node.js
FROM node:18-alpine

# 2. Establecer el directorio de trabajo
WORKDIR /app

# 3. Copiar los archivos de dependencias e instalarlas
COPY package*.json ./
RUN npm install

# 4. Instalar curl para el healthcheck
RUN apk update && apk add --no-cache curl

# 5. Copiar el resto del código de la app de resultados
COPY . .

# 6. Exponer el puerto en el que la aplicación escucha
EXPOSE 3000

# 7. Comando para ejecutar la aplicación
CMD ["npm", "start"]
