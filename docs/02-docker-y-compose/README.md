# Solución reto semana 02

## Ejercicio
Vas a crear un entorno multi-servicio que incluya:

- vote: una app Flask que permite votar (gato o perro)
- worker: un servicio Node.js que procesa los votos
- result: una app Node.js que muestra los resultados en tiempo real
- redis: almacén temporal de votos
- postgres: base de datos persistente

## Asignación de Puertos por Servicio

| Servicio | Descripción | Puerto | Uso y Exposición |
| :--- | :--- | :--- | :--- |
| **Vote** | Interfaz de usuario para emitir votos (Flask). | `80` | **Expuesto (HTTP)**. Es el punto de acceso para la interfaz de votación. |
| **Result** | Muestra los resultados en tiempo real (Node.js + WebSocket). | `3000` | **Expuesto**. Permite visualizar los resultados de la votación. |
| **Redis** | Almacenamiento temporal de votos en memoria. | `6379` | **Interno**. Se usa para la comunicación entre los servicios `vote` y `worker`. |
| **Worker** | Procesa votos de Redis y los guarda en PostgreSQL (Node.js). | — | **Interno**. No expone ningún puerto; se comunica dentro de la red de contenedores. |
| **PostgreSQL**| Base de datos relacional para almacenar los resultados. | `5432` | **Interno**. El servicio `worker` se conecta a este puerto para persistir los datos. |

> **Nota:** Antes de levantar los contenedores, es fundamental verificar que los puertos `80` y `3000` no estén siendo utilizados por otras aplicaciones en tu sistema para evitar conflictos.

## Tareas del desafío

- Crear los Dockerfile personalizados para cada componente si aún no lo hiciste.
- Escribir el archivo docker-compose.yml que levante todos los servicios conectados.

Asegurate de que:
- Todos los servicios se comuniquen entre sí correctamente.
- Los contenedores levanten sin errores.
- Los puertos estén bien expuestos (5000, 5001, etc.).
- (Opcional) Agregá un volumen para persistir los datos de PostgreSQL.

## Recomendaciones
- Usá build context en Docker Compose para construir las imágenes desde cero.
- Usá una red personalizada para facilitar la comunicación entre servicios.

Levantá todo con:
```sh
docker compose up --build
```

Y probá que podés acceder a:

http://localhost → para votar

http://localhost:3000 → para ver los resultados

## Extra Challenge (Nivel Avanzado)
Si ya lograste levantar todo, podés ir un paso más allá:

- Agregá variables de entorno con .env
- Configurá depends_on correctamente
- Probá detener un contenedor (como worker) y ver cómo afecta a la app
- Agregá healthcheck a los servicios principales

## 1. Analisis de la solución

Para abordar la solución a este reto semanal tenemos hay que tener en cuenta que los retos son iterativos, eso significa que lo aprendido en el anterior reto se puede aplicar aquí

### 1.1 Puedes ver mi solución de la semana 01 [aquí](../01-automatizacion-con-vagrant-y-ansible/README.md)

### 1.2 Conocimientos de la semana 01 aplicables aquí

Primero que todo debemos tener en cuenta el flujo que utilizamos al levantar la maquina virtual y configuración de la aplicación para correrla

#### 1.2.1 Flujo
1. Creación de la maquina virtual
2. Instalación de software
3. Preparación de variables de entorno
4. Correr aplicación

#### 1.2.2 ¿Cómo vamos a trasladar lo aprendido en la semana 01 a Docker y compose?

Bastante fácil, entendemos que docker funciona con imagenes y contenedores, digamos que cada componente de la app (`vote`, `result`, `worker`) es una imagen y por cada imagen vamos a crear un contenedor.

ahora **¿cómo trasladamos el entendimiento de la maquina virtual aquí?**. Bastante sencillo básicamente cada componente va a tener su propia maquina virtual, dejamos de ver la aplicación como si la corrieramos todos juntos en una maquina virtual a que cada uno esté en su propio espacio aíslado del otro

Esto trae varios beneficios y una mejor segmentación del proyecto porque en caso de que falle el contenedor de `vote` sabemos que debemos entrar al contenedor de `vote` y revisar qué pasó, no hubo interferencia por instalar nodejs que necesita el contenedor de `result` o `worker`

Esto nos trae un mejor manejo de componentes de la aplicación pero trae otro y es la conexión, **¿cómo hacemos para que varias maquinas virtuales independientes se comuniquen entre ellas?**. Lo veremos a medida que realicemos la solución.

### 2. Creando Dockerfiles

Primero vamos desde lo esencial, o sea, lo independiente y luego lo vamos a agrupar con **compose**

En el analisis de la aplicación de la semana 01 que puedes ver [aquí](../01-automatizacion-con-vagrant-y-ansible/README.md#analisis-de-la-aplicación) los componentes `result` y `worker` corren en nodejs y `vote` con python

#### 2.1 ¿Qué sucede con postgresql y redis?

Son necesarios, sin embargo, deben ser independientes también y lo puedes imaginar de la siguiente manera:

Cuando creamos la maquina virtual le especificamos que permitirá acceder al puerto `80` del invitado (**Maquina Virtual**) a través del puerto `4999` del host (**Maquina Local**). Bien, imagina que en este caso la **Maquina virtual** es **un contenedor de docker** solo que menos complejo ya que no es necesario redireccionar puertos, entonces **¿cómo quedaría?** le decimos al contenedor que exponga un puerto en el cual él va a estar escuchando

```yml
EXPOSE 80
```

En conclusión un ejemplo de Dockerfile sería

```yml
# 1. Usar una imagen base oficial de Python
FROM python:3.9-slim

# 2. Establecer el directorio de trabajo dentro del contenedor
# Equivale a la carpeta vagrant donde en la semana 01 clonamos el repositorio de git aquí
WORKDIR /app

# 3. Copiar el archivo de dependencias e instalarlas
# Se hace en un paso separado para aprovechar el cache de Docker
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
```

**¿Entiendes cómo se repite el mismo proceso de creación, instalación de requerimientos y correr la app?** Solo que ahora es para cada componente individualmente. Este mismo proceso lo debe tener cada uno `vote`, `result`, `worker`

1. vote
2. result
3. worker
4. postgresql
5. redis

Es sencillo para los tres componentes que tenemos locales, pero **¿cómo preparamos `postgresql` y `redis`?**

### 3. Creando docker-compose

Ya sabemos cómo crear nuestras imagenes de nuestros tres componentes, ahora vamos a empezar a orquestar todo y para esto utilizamos **docker compose**

#### 3.1 Creando el nombre de nuestra docker compose
Empezamos con la etiqueta más básica y es el nombre de nuestra orquesta

```yml
name: roxs-voting-app
```

#### 3.2 Creando la red en la que vamos a meter nuestros contenedores
Ahora vamos a organizar dónde vamos a orquestar nuestros contenedores, para esto utilizamos las redes. **Sería como la mesa de trabajo y sobre ella vamos a servir los platos (cada servicio)**

```yml
networks:
  voting_app_network:
    driver: bridge
```

de **esta manera creamos la mesa de trabajo (network) de nuestra aplicación** y será driver bridge para la comunicación interna de nuestros contenedores

empecemos con uno de los más complejos, la base de datos, la recomendación es siempre empezar por aquí

### 4. Postgresql en docker compose

Dentro de nuestros servicios tendrémos la base de datos y lo haremos de la siguiente manera

```yml
services:
    # Nombre del servicio, este es el que va en los archivos ".env"
    postgres:
        # Nombre del contenedor dentro de nuestra app roxs-voting-app
        container_name: postgres_db
        # Imagen base de la base de datos
        image: postgres:16.1-alpine
        # Variables de entorno
        environment:
            - ./postgres.env
        # Volumen para la persistencia de datos nombre:ubicación
        volumes:
            - db-data:/var/lib/postgresql/data
        # Red que sería como decir a qué mesa de trabajo va a pertenecer
        networks:
            - voting_app_network
        # Healthcheck para comprobar que la base de datos está escuchando o encendida
        healthcheck:
            test: ["CMD-SHELL", "pg_isready -U postgres"]
            interval: 5s
            timeout: 5s
            retries: 5
```

Ahora bien... **¿de dónde salieron todas estos datos?**

La mayoría de datos se obtienen desde la documentación de la imagen [aquí](https://hub.docker.com/_/postgres) pero te lo resumo

Necesitamos proveer las siguientes variables de entorno para definir los datos de ingreso a la base de datos, puedes ver el ejemplo aquí: [postgres.env.example](../../postgres.env.example)

#### 4.1 Naming de variables de entorno
Acerca del naming de estos tipos de `.env` files la comunidad adopta dos tipos

1. `env.*`: En esta convención, el nombre del entorno se añade como una extensión. Es uno de los formatos más comunes.

- `.env.development`

- `.env.staging`

- `.env.production`

2. `*.env`: Esta alternativa mantiene la extensión .env al final, lo que puede ayudar a algunos editores de código como VS Code a reconocer y aplicar el resaltado de sintaxis correcto.

- `.development.env`

- `.staging.env`

- `.production.env`

En esta solución utilizamos ambos tipos ya que considero que tienen su justificación

En este caso optamos por dejarlo con `.env` al final para no generar algún tipo de incompatibilidad de no dejarlo con `.postgres` al final y lo tome como otra extensión

```
# postgres.env
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=votes
```

#### 4.2 Volumen para la persistencia de datos en postgresql
La documentación también nos provee la dirección donde es persistente la data de la base de datos

> /var/lib/postgresql/data

El volumen solo requiere el nombre del volumen y la dirección, puedes ver un ejemplo práctico con postgresql [aquí](https://dev.to/iamrj846/how-to-persist-data-in-a-dockerized-postgres-database-using-volumes-15f0)

```yml
# Puede llamarse como quieras ejm:
- mi-data-persistente:/var/lib/postgresql/data
```

#### 4.3 Añadiendo postgresql a nuestra red 
La network solo requiere apuntar a la red que ya tenemos definida y creamos en el paso [3.2 Creando la red en la que vamos a meter nuestros contenedores](#32-creando-la-red-en-la-que-vamos-a-meter-nuestros-contenedores)

> voting_app_network

Los healthchecks lo puedes plantear como comandos de confirmación, por ejemplo cuando se monte la base de datos al final vamos a querer querer confirmar que esté funcionando, postgresql oficial nos provee este comando `pg_isready` nosotros utilizamos `-U postgres` para comprobar la conexión especificamente con el usuario **postgres**, sin embargo, no hay problema de solo ejecutarlo

la salida es la siguiente


```sh
pg_isready -U postgres
# Salida
/var/run/postgresql:5432 - accepting connections
```

Tenemos otros parametros para estas validaciones, en este caso `interval` es el intervalo de tiempo que Docker esperará entre un chequeo y el siguiente, `timeout`  Es el tiempo máximo que Docker está dispuesto a esperar por una respuesta a un solo chequeo y por último `retries` es el número de intentos fallidos consecutivos que Docker tolerará antes de rendirse y marcar el contenedor como "no saludable" (**unhealthy**).

### 5. Redis en docker compose

Redis no necesita tanta configuración como postgresql, funciona como un servidor el cual va a estar escuchando en su respectivo puerto pero sucede lo mismo, **¿Cómo sabemos que la instalación fue correcta, que está escuchando realmente?**

Al igual que postgres, Redis también tiene su propio comando para confirmar el status del servicio y validar la conexión: [`redis-cli ping`](https://redis.io/docs/latest/commands/ping/)

```sh
redis-cli ping
# Salida
PONG
```

```yml
services:
    redis:
        container_name: redis_cache
        image: redis:7.2-alpine
        networks:
        - voting_app_network
        healthcheck:
        test: ["CMD", "redis-cli", "ping"]
        interval: 1s
        timeout: 3s
        retries: 30
```

Con esto es suficiente para tener como "**Healthy**" estos dos servicios

Se puede empezar a probar cómo va quedando esta base

```sh
docker compose up --build
```

Luego de la construcción podemos comprobar los contenedores

```sh

docker ps
# Salida
8379c6ec66c0   redis:7.2-alpine         "docker-entrypoint.s…"   2 hours ago   Up 14 minutes (healthy)   6379/tcp                   redis_cache
f638ff7ee5c1   postgres:16.1-alpine     "docker-entrypoint.s…"   2 hours ago   Up 14 minutes (healthy)   5432/tcp                   postgres_db
```

Ahora están marcados como **healthy**, eso significa que se desplegaron y ahora estamos seguros de que están **correctamente provisionados**, puedes aprender más sobre **Healthchecks** en docker [**aquí**](https://medium.com/@saklani1408/configuring-healthcheck-in-docker-compose-3fa6439ee280)

### 6. Manejo de variables de entorno en docker compose

Para nuestros tres servicios locales (`vote, result y worker`) tenemos variables de entorno que podemos usar, pero no todos los servicios requieren las mismas variables, a diferencia de la semana 01 en la que los tres servicios estaban en una misma **Maquina virtual** ahora tenemos una **Maquina virtual** por servicio, **ahora sí podemos aplicar las variables de entorno correspondientes a cada servicio** y vamos a aplicar **Don't Repeat Yourself (DRY)**, consiste en usar un archivo `.env` en el `root` del proyecto el cual va a tener variables de entorno que los tres servicios van a utilizar, en este caso las **credenciales de la base de datos** y un `.env.local` que va a estar en cada componente de la aplicación `vote, result y worker` en caso de necesitarlo. Cada servicio puede tener multiples `.env` files

```yml
env_file:
    - ./.env
    - ./app/vote/.env.local
```

### 7. Vote en docker compose

Ya teniendo **Redis** y **Postgresql** provisionados en la aplicación ahora nos queda empezar a montar los servicios locales de nuestra `app`

```yml
services:
    vote:
        container_name: vote
        build: ./app/vote
        ports:
            - "127.0.0.1:80:80"
        env_file:
            - ./.env
            - ./app/vote/.env.local
        networks:
            - voting_app_network
        depends_on:
            redis:
                condition: service_healthy
            postgres:
                condition: service_healthy
        healthcheck:
            test: ["CMD", "curl", "-f", "http://localhost:80/healthz"]
            interval: 30s
            timeout: 10s
            retries: 5
```

#### 7.1 Puerto de vote 
Para entender los puertos en **Docker** vamos a traducir esto `"127.0.0.1:80:80"` y es bastante sencillo, tenemos nuestra **Maquina local** que es donde estamos levantando el **docker compose** y el **Contenedor** que viene siendo como una **Maquina virtual** para ese servicio y haremos algo parecido que en el ejercicio a la semana 01

- `127.0.0.1:3000`: Has creado un puente o una redirección desde el puerto `3000` **de tu PC (el "host")** hacia el contenedor

- `3000`: El servicio, **dentro de su contenedor (Maquina virtual)**, está escuchando en el puerto `3000`

#### 7.2 Dependencias de vote
Para las dependencias que tiene este servicio tendrán una condición y será hasta que `redis` y `postgres` se marquen como **healthy**, si esto no sucede el contenedor de `vote` debería quedar en un estado indefinido 

```yml
depends_on:
    redis:
        condition: service_healthy
    postgres:
        condition: service_healthy
```

#### 7.3 Healthcheck de vote
Cuando revisamos el código de [`app.py`](../../app/vote/app.py) en `vote` encontramos que hay una ruta dispuesta para probar la salud del servicio y es la que utilizaremos para el healthcheck de nuestro servicio

```py
@app.route("/healthz")
def healthz():
    """Health check endpoint"""
```

#### 7.4 ¿Cómo podemos hacer un healthcheck manual?
Este paso lo agrego de manera informativa, pero es para entender qué es lo que sucede en el contenedor. Entonces poniendonos en contexto, cuando termina de provisionarse el contenedor y esté en el paso del healthcheck lo que hará docker compose es:

1. ingresar al contenedor (Maquina virtual)
2. Ejecutar el `test` y de acuerdo a los resultados ya le pone el estado al contenedor

Bastante sencillo y nosotros lo podemos hacer de la siguiente manera

```sh
docker ps
# Salida
CONTAINER ID   IMAGE                    COMMAND                  CREATED          STATUS                    PORTS                      NAMES
ef654b4c8df4   roxs-voting-app-vote     "python3 app.py"         59 minutes ago   Up 59 minutes (healthy)   127.0.0.1:80->80/tcp       vote

# Entramos al contenedor
docker exec -it ef654b4c8df4 /bin/sh
# Debe aparecer # al inicio, luego ejecutamos el comando que tenemos en el healthcheck
curl -f http://localhost:80/healthz
# Respuesta del curl
{
  "database": "OK",
  "hostname": "ef654b4c8df4",
  "redis": "OK",
  "service": "vote-service",
  "status": "OK"
}
```

El docker compose lo determina el stado a partir de las **respuestas HTTP** en este caso responde con **status 200** por lo tanto el servicio puede ser calificado como **healthy**

#### 7.5 ¿Cómo funciona depends_on con el healthcheck?

Supongamos que el servicio de `redis` no logra obtener su status **Healthy**, el contenedor que dependa de este **Healthy** en redis se va a crear, va a correr pero no va a ejecutar la lógica, porque la condición que requiere no se cumple, entra en un estado **indefinido** esperando a que redis obtenga su status **Healthy**

### 8. Worker en docker compose

Este parece ser el más retador ya que no expone un puerto en la aplicación, sin embargo, cuando hicimos la prueba del [**healtcheck manual**](#74-cómo-podemos-hacer-un-healthcheck-manual) para entender qué es lo que hace **docker compose** nos damos cuenta que nosotros nos conectamos al contenedor, en pocas palabras, entramos al contenedor y ejecutamos los comandos, por lo que el **healthcheck** a pesar de que no exponga un puerto a nuestra maquina local, dentro del contenedor existe y está escuchando

```yaml
service:
    worker:
        container_name: worker
        build: ./app/worker
        env_file:
            - ./.env
        networks:
            - voting_app_network
        depends_on:
        redis:
            condition: service_healthy
        postgres:
            condition: service_healthy
        healthcheck:
            test: ["CMD", "curl", "-f", "http://localhost:3000/healthz"]
            interval: 30s
            timeout: 10s
            retries: 5
```

Este servicio utiliza una base similar a `Vote`, solo que no es necesario exponer un puerto de acuerdo a la [**asignación de puertos por servicio**](#asignación-de-puertos-por-servicio)

### 9. Result en docker compose

Aquí aplicamos la misma base de contenedor que en `Vote`, a diferencia de `Worker` este servicio sí necesita exponer un puerto

```yml
services:
    result:
        container_name: result
        build: ./app/result
        ports:
        - "127.0.0.1:3000:3000"
        env_file:
        - ./.env
        - ./app/result/.env.local
        networks:
        - voting_app_network
        depends_on:
        postgres:
            condition: service_healthy
        healthcheck:
        test: ["CMD", "curl", "-f", "http://localhost:3000/healthz"]
        interval: 30s
        timeout: 10s
        retries: 5
```


### 10. Ejecutando docker compose

Ahora que tenemos los cinco componentes que planteamos desde el inicio podemos arrancar nuestra orquesta, tenemos:

1. Red propia para la aplicación (Mesa de trabajo)
2. Contenedores dentro de la red
3. Healthchecks para todos los componentes de nuestra aplicación

Empezamos con la construcción del docker compose con

```sh
docker compose up --build
```

Podemos ver el status de nuestros contenedores de la siguiente manera

```sh
docker ps
# Salida
CONTAINER ID   IMAGE                  COMMAND                  CREATED         STATUS                            PORTS      NAMES
659b021485a2   postgres:16.1-alpine   "docker-entrypoint.s…"   5 seconds ago   Up 3 seconds (health: starting)   5432/tcp   postgres_db
c863b6f9cfd4   redis:7.2-alpine       "docker-entrypoint.s…"   5 seconds ago   Up 3 seconds (healthy)            6379/tcp   redis_cache

# Luego de unos segundos vuelve a intentar
docker ps
# Salida
CONTAINER ID   IMAGE                    COMMAND                  CREATED         STATUS                           PORTS                      NAMES
25b760946dcb   roxs-voting-app-vote     "python3 app.py"         8 seconds ago   Up 1 second (health: starting)   127.0.0.1:80->80/tcp       vote
23bd835b00f4   roxs-voting-app-worker   "docker-entrypoint.s…"   8 seconds ago   Up 1 second (health: starting)                              worker
62d825bdee8f   roxs-voting-app-result   "docker-entrypoint.s…"   8 seconds ago   Up 1 second (health: starting)   127.0.0.1:3000->3000/tcp   result
659b021485a2   postgres:16.1-alpine     "docker-entrypoint.s…"   8 seconds ago   Up 6 seconds (healthy)           5432/tcp                   postgres_db
c863b6f9cfd4   redis:7.2-alpine         "docker-entrypoint.s…"   8 seconds ago   Up 6 seconds (healthy)           6379/tcp                   redis_cache

# Vuelve a intentar más tarde aún
docker ps
# Salida
CONTAINER ID   IMAGE                    COMMAND                  CREATED              STATUS                    PORTS                      NAMES
25b760946dcb   roxs-voting-app-vote     "python3 app.py"         About a minute ago   Up 54 seconds (healthy)   127.0.0.1:80->80/tcp       vote
23bd835b00f4   roxs-voting-app-worker   "docker-entrypoint.s…"   About a minute ago   Up 54 seconds (healthy)                              worker
62d825bdee8f   roxs-voting-app-result   "docker-entrypoint.s…"   About a minute ago   Up 54 seconds (healthy)   127.0.0.1:3000->3000/tcp   result
659b021485a2   postgres:16.1-alpine     "docker-entrypoint.s…"   About a minute ago   Up 59 seconds (healthy)   5432/tcp                   postgres_db
c863b6f9cfd4   redis:7.2-alpine         "docker-entrypoint.s…"   About a minute ago   Up 59 seconds (healthy)   6379/tcp                   redis_cache
```

Ves cómo el status va cambiando en los contenedores y cómo los tres contenedores locales `vote`, `result` y `worker` esperan a que `redis` y `postgres` se marquen como **Healthy** para iniciar sus respectivos **healthchecks**

### 11. Comprobando la red de nuestra aplicación

Ahora todo está corriendo y parece muy mágico que con solo tres líneas hayamos creado una red, pero ¿cómo se ve esto internamente?

```sh
docker network ls
# Salida
NETWORK ID     NAME                                 DRIVER    SCOPE
31a4ba070cb1   roxs-voting-app_voting_app_network   bridge    local

# Vas a ver muchas networks pero vas a buscar la que creamos y está constituída por el name del docker compose y el nombre de la network

# Inspeccionar network
docker inspect network roxs-voting-app_voting_app_network

# Vas a ver como salida un objeto json muy grande, pero lo que nos interesa es la propiedad Containers

# Debes buscar esto
"Containers": {
            "23bd835b00f403e4c1fb05de97dc4e912c5b6bbee0e9460063ec8693a2886648": {
                "Name": "worker",
                "EndpointID": "39bff729bc872447efca93f327cf0136ec0bbfa91ae854d190cc3972dccc9da5",
                "MacAddress": "8a:4e:e5:4e:97:a4",
                "IPv4Address": "172.21.0.4/16",
                "IPv6Address": ""
            },
            "25b760946dcb1d10df89efc8ebe81fea8a53ec078ce5593a143a4989830cd4d1": {
                "Name": "vote",
                "EndpointID": "22c35209c6b3b46672464acac2295e3b1119cc132d6d752633e414e7c5253534",
                "MacAddress": "d6:d9:6b:4e:55:de",
                "IPv4Address": "172.21.0.6/16",
                "IPv6Address": ""
            },
            "62d825bdee8f1ac50e3365c074fa4f2ecc253934a63ed564ee4a254468782745": {
                "Name": "result",
                "EndpointID": "2b0b9e99aa29f4d0448db8619713d0e0f491503954d61f93e5e266a6b97a1ece",
                "MacAddress": "96:59:19:7f:38:4e",
                "IPv4Address": "172.21.0.5/16",
                "IPv6Address": ""
            },
            "659b021485a2d383dcd12dc9f98cd49b80ebb454a8e5023c74cdf739181da586": {
                "Name": "postgres_db",
                "EndpointID": "978d9f54a4351f59dc4f7682de7d41feded2d5b31cf95406e6fb5fde2105ddf0",
                "MacAddress": "42:39:5c:06:3b:ba",
                "IPv4Address": "172.21.0.3/16",
                "IPv6Address": ""
            },
            "c863b6f9cfd4f5c2d9d92206093186e5c44175c496c7c07c174ae8ddda70a779": {
                "Name": "redis_cache",
                "EndpointID": "e7a0f78e643457bebf4698663fd7ccc7f446be1c75c1cd5a387a7e326950ccb4",
                "MacAddress": "a6:31:54:d0:8c:39",
                "IPv4Address": "172.21.0.2/16",
                "IPv6Address": ""
            }
        }
```

de esta manera comprobamos la Network de la aplicación

### 12. Comprobando la persistencia de los datos

Para comprobar la persistencia es bastante sencillo, podemos tumbar toda la aplicación con

```sh
docker compose down
```

Vas a ver cómo tus contenedores dejaron de existir, ahora vuelve a arrancar todo

```sh
docker compose up --build
```

Si verificas los puertos vas a notar cómo la data sigue existiendo, ahora bien, **¿qué pasa si quieres eliminar el volumen?** Puedes correr

```sh
docker compose down -v
```

esta `-v` nos ayudará a eliminar los volumenes atados a este **docker compose**

### 13. ¿Qué sucede si apagamos un servicio?

El problema depende del servicio que se va a apagar y su impacto en la aplicación, por ejemplo si apagamos el servicio de `redis` vamos a empezar a tener errores de sincronización de votos, si apagamos `postgresql` vamos a dejar de guardar información y la aplicación quedaría quieta porque los servicios no encuentran **conexión con la base de datos**, depende de su importancia vamos a notar errores en la aplicación, cuando hablamos de **docker** lo que logramos notar es que dejaría de pertenecer a la red de la aplicación, pero es porque está apagado, cuando vuelve a prender hará todo su proceso de arranque normal y volverá a la red

### 14. Archivos del ejercicio

Los archivos `.env` originales están ignorados por git ya que no es buena práctica exponer credenciales de esta forma, en lugar de eso se dejaron archivos `.env.example` los cuales tienen una misma estructura y datos dummy para poder dar a conocer la estructura que necesitan, solo basta que en el mismo lugar que lo tomaste por ejemplo en el `root` **/.env.example** crees un archivo en ese mismo lugar sin la extensión example **/.env** y pegues el contenido del ejemplo, de esa manera debe de funcionar todo correctamente

#### Docker Compose: root del proyecto [docker-compose.yml](../../docker-compose.yml)

#### Dockerfiles: dentro del root de cada servicio dentro de app: [Dockerfile (vote)](../../app/vote/Dockerfile)

