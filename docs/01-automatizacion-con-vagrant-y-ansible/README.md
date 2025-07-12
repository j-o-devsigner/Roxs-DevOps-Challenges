# Solución reto semana 01

## Ejercicio
¿Qué vas a hacer?

- Clonar el repositorio del proyecto educativo
- Usar Vagrant para levantar el entorno
- Automatizar configuraciones básicas
- Ejecutar los tres servicios (Vote, Worker, Result)
- Validar que los datos fluyan desde la votación hasta la visualización


## Arquitectura
```
[ Vote (Flask) ] ---> Redis ---> [ Worker (Node.js) ] ---> PostgreSQL
                                       ↓
                               [ Result (Node.js) ]
```

## Actividades
- Usar un Vagrantfile para levantar una máquina Ubuntu local
- Automatizar la instalación de Redis, PostgreSQL, Python y Node.js con Ansible
- Ejecutar manualmente cada componente de la app
- Validar que puedas votar y ver el resultado en el navegador

## Resultado Esperado
- App funcional en entorno local
- Automatización básica de dependencias
- Experiencia práctica de orquestar servicios sin Docker (aún)

## Arquitectura de la Aplicación de Votación

A continuación, se presenta una tabla con el desglose de los componentes del sistema:

| Servicio   | Descripción                                         | Puerto           |
| :--------- | :-------------------------------------------------- | :--------------- |
| **Vote**   | Interfaz de usuario para que los usuarios emitan su voto (construido en Flask). | `80`             |
| **Result** | Muestra los resultados de la votación en tiempo real (Node.js + WebSocket). | `3000`           |
| **Redis**  | Base de datos en memoria que almacena temporalmente los votos recibidos.      | `6379`           |
| **Worker** | Proceso en segundo plano (Node.js) que lee los votos de Redis y los persiste en PostgreSQL. | — (sin puerto expuesto) |
| **PostgreSQL**| Base de datos relacional donde se almacenan permanentemente los resultados. | `5432`           |

## Analisis de la aplicación

La aplicación nos propone dos componentes **Result** y **Worker** con NodeJS ya que tienen un **package.json** y **vote** con python ya que tiene **requirements.txt** lo que nos busca sacar del molde de que en los proyectos solo se trabaja con una sola tecnología.

como DevOps es un plus saber cómo funcionan las tecnologías para entender su conexión y orquestación, sin embargo, es importante entender los requerimientos que necesita la aplicación

### Analisis del componente **``vote``** y su responsabilidad en la App

si revisamos el app.py y requirements.txt encontramos muchas dependencias, se logra entender que está intentando conectar a una base de datos

```py
# Conexión con postgres database
def get_pg_conn():
    try:
        conn = psycopg2.connect(
            host=os.getenv('DATABASE_HOST', 'database'),
            user=os.getenv('DATABASE_USER', 'postgres'),
            password=os.getenv('DATABASE_PASSWORD', 'postgres'),
            dbname=os.getenv('DATABASE_NAME', 'votes')
        )
```

```py
# Env vars
REDIS = os.getenv('REDIS_HOST', "localhost")

# Conexión con redis
def get_redis():
    if not hasattr(g, 'redis'):
        try:
            g.redis = Redis(host=REDIS, db=0, socket_timeout=5)
```

No sabemos en su totalidad cómo funciona pero ya descubrimos estos dos elementos que requiere para funcionar.

### Planteando correr el componente **``vote``**

Ahora entendiendo que vote necesita estas dos conexiones las vamos a necesitar proveer, en este caso es una buena practica por parte del equipo de desarrollo utilizar variables de entorno para correr y tienen un default que sería su segundo argumento como dice en su documentación, que en caso de no recibir el primero, utilizará el segundo

Ejemplo:
```py
REDIS = os.getenv('REDIS_HOST', "localhost")
```

Si se provee la variable de entorno lo que haya dentro de **``REDIS_HOST``** es lo que se utilizará en la variable, si no existe utilizará el segundo valor por defecto **``localhost``**

```py
(function) def getenv(
    key: str, # Valor inyectado por environment
    default: _T@getenv # Valor por defecto
) -> (str | _T@getenv)
Get an environment variable, return None if it doesn't exist.
The optional second argument can specify an alternate default.
key, default and the result are str.
```

Haciendo un mapeo necesitamos cinco variables y el mejor elemento para este caso es un archivo **``.env``**

```
REDIS_HOST
DATABASE_HOST
DATABASE_USER
DATABASE_PASSWORD
DATABASE_NAME
```

### Analisis del componente **``worker``** y su responsabilidad en la App

Este componente se encarga de sincronizar los datos de la base de datos con redis, está construído con nodejs y encontramos una conexión a base de datos y adicionalmente va a necesitar que le dispongamos de un puerto que viene por defecto en el `3000` en el código y no disponemos de variable de entorno para este servicio

```js
// Configuración mejorada de timeouts
const DB_CONFIG = {
  host: process.env.DATABASE_HOST || "database",
  user: process.env.DATABASE_USER || "postgres",
  password: process.env.DATABASE_PASSWORD || "postgres",
  database: process.env.DATABASE_NAME || "votes",
  connectionTimeoutMillis: 10000,
  idleTimeoutMillis: 30000,
  query_timeout: 10000,
};
```

```js
const port = 3000;
// Iniciar servidor de métricas
app.listen(port, () => {
  console.log(`Worker metrics server listening at http://0.0.0.0:${port}`);
});
```

### Planteando correr el componente **``worker``**

En resumen tendríamos el mismo caso que en el componente de `vote` que necesitamos variables de entorno en archivo **`.env`** con solo los datos de la base de datos

```
DATABASE_HOST
DATABASE_USER
DATABASE_PASSWORD
DATABASE_NAME
```

### Analisis del componente **``result``** y su responsabilidad en la App

En general encontramos el mismo caso que el componente `worker` corriendo en NodeJS y utilizando variables de entorno para la conexión con la base de datos y una variable de entorno adicional que nos va a ayudar en el despliegue futuro `APP_PORT`

```js
// Loading environment variables
const port = process.env.APP_PORT || 3000;
const dbhost = process.env.DATABASE_HOST || 'database';
const dbname = process.env.DATABASE_NAME || 'votes';
const dbuser = process.env.DATABASE_USER || 'postgres';
const dbpass = process.env.DATABASE_PASSWORD || 'postgres';
```

### Planteando correr el componente **``result``**

Ahora que entendemos que hay un conflicto en las variables por defecto de los servicios que tenemos en `worker` y `result` luchando por el puerto `3000` vemos que el componente `result` es más flexible y es el que podemos cambiar sin necesidad de tocar el código de la aplicación

Aunque podemos instruír un mejor planteamiento de preconfiguración en la app en este caso nos vamos a adaptar de esta manera para no tener que modificar el código base de la aplicación

### Planteando el Vagrantfile

La maquina virtual que vamos a levantar no va a tener una interfaz gráfica (aunque es posible lograrlo), sin embargo, lo que vamos a hacer es crear un puente entre la **VM** (`Virtual Machine`) y nuestra **maquina local** para **redireccionar el tráfico de nuestros puertos de maquina local** a los de la **VM**

#### ¿Cómo redireccionar el tráfico?

En nuestro bloque al crear nuestra VM en el vagrantfile

```sh
# Nuestro bloque inicia aquí
Vagrant.configure("2") do |config|
  # Se configura la red para reenviar el tráfico de nuestro host, al 
  config.vm.network "forwarded_port", guest: 80, host: 4999
# Aquí finaliza el bloque
end
```

**Vagrant forwarded_port documentación**: [aquí](https://developer.hashicorp.com/vagrant/docs/networking/forwarded_ports)

Lo que quiere decir es que permitirá acceder al puerto `80` del invitado (**Maquina Virtual**) a través del puerto `4999` del host (**Maquina Local**).

Ya solucionamos el problema más complejo y es lograr este puente entre nuestra maquina y la maquina virtual, con esto solucionamos la mitad de nuestros problemas

### Provisionando Ansible

Para que nuestro `Vagrantfile` Pueda leer nuestros archivos de ansible la recomendación es que tengamos nuestro `playbook.yml` listo

De acuerdo a la documentación [**Ansible and Vagrant**](https://developer.hashicorp.com/vagrant/docs/provisioning/ansible_intro) la declaración de este paso se realiza de la siguiente manera

```sh
# Nuestro bloque inicia aquí
Vagrant.configure("2") do |config|
  # Se provisiona ansible
  config.vm.provision "ansible" do |ansible|
    # Apuntamos a nuestro playbook.yml
    ansible.playbook = "provisioning/playbook.yml"
  end
# Aquí finaliza el bloque
end
```

Ahora bien, aunque la tarea de ansible es preparar nuestro entorno para que nosotros solo entremos y ejecutemos la aplicación lo ideal es no utilizar un playbook con todo, lo recomendable es modularizar en caso de que crezca la aplicación

### Preparando Ansible

Ahora que entendemos la aplicación y sus requerimientos para funcionar vamos a plantear esta solución de manera sencilla.

La maquina virtual necesita software para funcionar, el que necesitamos para nuestra app:

`redis`, `postgresql` y `nodejs`

cada uno de estos va a ser un rol en nuestro playbook, adicionalmente vamos a tener dos roles adicionales, uno será `common` el cual va a instalar software que necesitamos como **git** y **python**. Por ultimo vamos a tener un rol que se llama `app` que se encargará de preparar el repositorio y crear las variables de entorno

#### ¿Clonar repositorio en la maquina virtual o sincronizar carpetas?

En este caso se prefirió preparar el entorno con `git` para poder clonar el proyecto y **ambos caminos tienen sus respectivos casos de uso**

**Caso 1:** Puede que nosotros entremos a modificar algo en el código y necesitemos exclusivamente estos cambios que realizamos y en ese caso se puede sincronizar la carpeta, esta sería la documentación: [**Synced-Folders**](https://developer.hashicorp.com/vagrant/docs/synced-folders/basic_usage)


**Caso 2:** Para mantener siempre el código actualizado es mejor clonar el repositorio y además de que el reto no requiere que modifiquemos algo en el código de los componentes

#### Seguridad en Ansible

En general algo que siempre debes de estar pensando es: **¿Cómo hago para no exponer contraseñas en código?** A nivel de desarrollo existen las variables de entorno, pero en nuestro caso probablemente vamos a trabajar con más personas y el código de la infraestructura debe de estar en algún lugar, no podemos subir los archivos de provisión con contraseñas reales por seguridad, en este caso utilizaremos un archivo `config.yml` el cual va a tener las variables con estos datos sensibles y adicionalmente **lo vamos a ignorar desde el `.gitignore` en el repositorio para que no se suba** y dejaremos un archivo `config.example.yml` solo con el propósito de dar a conocer la estructura que requiere nuestra infraestructura

```yml
# Declaración variables config.example.yml
database_host: "localhost"
database_user: "postgres"
database_password: "postgres"
database_name: "votes"
redis_host: "localhost"
app_port: 3001
```

Ahora bien, habíamos mencionado que cada componente requiere un archivo `.env` para cada componente de la aplicación, pero lo que haremos es crear estas variables general en la maquina virtual y que todos los componentes puedan acceder a las variables necesarias. **Ya que todos los tres componentes corren en una misma maquina**, todos tienen acceso, sin embargo, cuando pasemos a `docker` cada componente de la aplicación va a tener su propio contenedor separado y vamos a poder segmentar las llaves brindando únicamente las necesarias por contenedor, siempre es bueno buscar que cada componente tenga lo justo y necesario para su funcionamiento, no más.

```yml
# role app leyendo las variables de config
export DATABASE_HOST='{{ database_host }}'
export DATABASE_USER='{{ database_user }}'
export DATABASE_PASSWORD='{{ database_password }}'
export DATABASE_NAME='{{ database_name }}'
export REDIS_HOST='{{ redis_host }}'
export APP_PORT='{{ app_port }}'
```

#### Resumen del playbook

Ahora que segmentamos los roles y tienen sus responsabilidades solo queda llamarlos desde el playbook el cual va a provisionar las variables para los roles

```yml
---
- hosts: all
  become: true

  vars_files:
    - config.yml

  roles:
    - common
    - postgresql
    - nodejs
    - redis
    - app
```

De esta manera solo queda llamarlo desde nuestro Vagrantfile

```sh
# Configuración de Ansible
  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook = "provisioning/playbook.yml"
  end
```

### Ejecutando la configuración completa

Ahora que todo está ensamblado lo que necesitamos es correr

```sh
# Correr el Vagrantfile (debe ser ejecutado donde esté el archivo)
vagrant up

# comprobar conexión y variables de entorno

# Conectar a la maquina virtual
vagrant ssh

# Comprobar las variables de entorno
env | grep DATABASE

# Salida
DATABASE_NAME=votes
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
DATABASE_HOST=localhost
```


Y como último paso adicional vamos a utilizar un `setup.sh` el cual va a correr nuestros componentes al terminar la configuración de la **Maquina virtual**

En este caso los comandos básicos para correr la aplicación y utilizamos `nohup` para que cuando se cierre sesión no se pierda el proceso y el puerto que utiliza `-E` para que cuando ejecutemos `sudo` no cambie el contexto y perdamos las variables de entorno, la unica manera de terminar el proceso del componente `vote` es cerrado la terminal completa y así liverará el puerto 80

de esta manera utilizando 
```sh
vagrant up
```

Vamos a crear la **Maquina virtual**, la **Configuración del ambiente** y la **Ejecución de los componentes**

El resultado final debe salir

```sh
default: --- ¡Aplicación lanzada! Puedes acceder a ella desde tu navegador. ---
default: Visita http://localhost:4999 para ver la aplicación en acción.
default: Visita http://localhost:5001 para ver resultados de votación.
```

Si quieres destruír todo lo construído sal de la **Maquina virtual** con `exit` y ejecuta

```sh
vagrant destroy -f
```

Con eso podemos concluír el reto de la semana 01, cualquier duda o mejora será bien recibida.

## Archivos del ejercicio

### Vagrantfile: /root del proyecto [Vagrantfile](../../Vagrantfile)

### Ansible configuración: carpeta /provisioning [Playbook](../../provisioning/playbook.yml)