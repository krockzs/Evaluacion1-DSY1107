# DSY1107 — EP5 | Manual operativo para la demostración en clases

**Proyecto:** Kafka de dos brokers + Kafka Streams en AWS + Kafka UI + Prometheus + Grafana.  
**Rama:** ep5-app. **Equipo del operador:** 🔴 Ryzen / NEEBLES OS.  
**Punto de entrada de comandos:** \`bash ep5/operar.sh <subcomando>\`.

> **No utilizar el README.md principal como guía de EP5.** Ese README documenta la evaluación anterior (Angular/Oracle/API Gateway) y no describe esta topología Kafka Streams.

## 1. Arquitectura que debes tener presente

| Rol | EC2 | IP privada | Software |
| --- | --- | --- | --- |
| APP | i-09732ce35a9b0e22b | 172.31.25.21 | Ubuntu, Java 21, Maven, Kafka Streams, systemd; salto SSH público |
| Kafka-1 | i-007b3c21d4d0decea | 172.31.91.91 | Docker, broker 1, ZooKeeper único, Kafka UI :8080 |
| Kafka-2 | i-00ac1f46c3ddd6c04 | 172.31.27.158 | Docker, broker 2 |
| Monitoring | i-0e3af62685c90f028 | 172.31.69.49 | Docker Compose, Prometheus, Kafka Exporter y Grafana |

**Región:** us-east-1. **Perfil AWS local:** pedidos360. **VPC:** vpc-0eaa5603256f0610f.  
La IP pública de APP se obtiene dinámicamente con AWS CLI: **no copiar direcciones públicas antiguas al comando**.

Flujo: productor -> \`ventas-raw\` -> Kafka Streams -> \`ventas-agregadas\` / \`ventas-raw-dlq\`. Kafka Exporter consulta ambos brokers; Prometheus recopila las métricas cada 15 s; Grafana las visualiza. **Kafka-1 contiene el único ZooKeeper**, de modo que el laboratorio no tiene alta disponibilidad total del plano de coordinación.

## 2. Preparación del Ryzen

1. Iniciar sesión en **AWS Academy**, comprobar que el laboratorio AWS esté activo y que las cuatro EC2 estén en estado \`running\`.
2. Tener las credenciales de AWS CLI bajo el perfil \`pedidos360\` y la llave \`~/Downloads/Pedidos360-Key.pem\`, con permisos \`0600\`.
3. Abrir la terminal del Ryzen e ingresar:

\`\`\`bash
cd ~/PROYECTOS/DUOC/Evaluacion1-DSY1107
git switch ep5-app
git status --short
git pull --ff-only origin ep5-app
bash -n ep5/operar.sh
bash ep5/operar.sh ayuda
\`\`\`

**Si \`git status --short\` presenta modificaciones**, revisarlas antes de actualizar. \`git pull --ff-only\` evita fusiones automáticas; no ejecutar \`reset --hard\` para resolverlo.

### Consultar EC2 sin cambiar nada

\`\`\`bash
bash ep5/operar.sh estado
\`\`\`

Si las instancias fueron detenidas previamente, desde el Ryzen pueden solicitarse sus arranques con AWS CLI. **Ese comando modifica recursos y puede generar consumo facturable**:

\`\`\`bash
aws ec2 start-instances --profile pedidos360 --region us-east-1 \
  --instance-ids \
  i-007b3c21d4d0decea \
  i-00ac1f46c3ddd6c04 \
  i-09732ce35a9b0e22b \
  i-0e3af62685c90f028
\`\`\`

Ejecutarlo **solo si aparecen detenidas**. Después esperar a que cada EC2 indique \`running\` y que los servicios estén accesibles. El hecho de estar \`running\` no prueba que todos los contenedores hayan arrancado. La instancia APP puede obtener una **nueva IP pública** al reanudarse; el operador la consulta automáticamente.

### Puertos del operador (solo localhost)

| Interfaz | Comando de terminal en Ryzen | URL desde Firefox |
| --- | --- | --- |
| Kafka UI | \`bash ep5/operar.sh kafka-ui\` | http://127.0.0.1:18080 |
| Grafana | \`bash ep5/operar.sh grafana\` | http://127.0.0.1:3000/d/dsy1107-kafka-ep5 |
| Prometheus | \`bash ep5/operar.sh prometheus\` | http://127.0.0.1:19090 |

Los tres accesos son **túneles SSH**; cada túnel permanece en primer plano. **Una terminal por túnel; mantener abierta mientras se usa y cerrar con Ctrl+C.** El puerto 19090 de Prometheus es local en Ryzen y reenvía al 9090 privado de Monitoring. Ni 18080, ni 19090, ni 3000 deben abrirse como puertos públicos en AWS.

El script de Grafana recupera la contraseña desde el servidor y procura copiarla al portapapeles sin escribirla en el TXT. Usuario: \`admin\`. **No compartir ni subir a Git capturas, contraseñas, ni el contenido de \`secrets/\`.** Si una terminal indica \`puerto local ocupado\`, comprobar si quedó un túnel anterior: no levantar dos en el mismo puerto.

## 3. Operación normal durante clases: cuatro terminales

**Terminal 1 — Kafka UI**

\`\`\`bash
cd ~/PROYECTOS/DUOC/Evaluacion1-DSY1107
bash ep5/operar.sh kafka-ui
\`\`\`

Abrir Firefox en http://127.0.0.1:18080. Inspeccionar **Brokers** (2), **Topics** y **Consumers**. Tópicos de negocio: \`ventas-raw\` (4 particiones), \`ventas-agregadas\` (2), \`ventas-raw-dlq\` (4). Kafka Streams también crea tópicos internos: no eliminarlos.

**Terminal 2 — Grafana**

\`\`\`bash
cd ~/PROYECTOS/DUOC/Evaluacion1-DSY1107
bash ep5/operar.sh grafana
\`\`\`

Abrir http://127.0.0.1:3000/d/dsy1107-kafka-ep5. Usar \`Last 15 minutes\` para pruebas cortas. El panel tiene 15 gráficos; monitorea 2 brokers, ISR/replicación, particiones, offset y lag. Los valores se actualizan cada 15 s; pueden demorar en reflejar una venta.

**Terminal 3 — Prometheus (opcional, para mostrar origen de métricas)**

\`\`\`bash
cd ~/PROYECTOS/DUOC/Evaluacion1-DSY1107
bash ep5/operar.sh prometheus
\`\`\`

Abrir http://127.0.0.1:19090. En consultas de Prometheus probar:

\`\`\`promql
kafka_brokers
sum(kafka_topic_partition_under_replicated_partition)
sum(kafka_topic_partition_in_sync_replica)
sum(kafka_consumergroup_lag{consumergroup="dsy1107-ventas-streams"} >= 0)
\`\`\`

**Terminal 4 — Operaciones y demostraciones**

\`\`\`bash
cd ~/PROYECTOS/DUOC/Evaluacion1-DSY1107
bash ep5/operar.sh estado
bash ep5/operar.sh topicos
bash ep5/operar.sh grupos
bash ep5/operar.sh prueba demo
bash ep5/operar.sh ultimo
\`\`\`

Durante la demo observar \`ventas-raw\`, \`ventas-agregadas\` y \`ventas-raw-dlq\` en Kafka UI; en Grafana observar la actividad por tópico y el lag del consumidor. El productor genera **6 ventas válidas + 1 duplicado + 1 inválido**; se espera agregado final \`saleCount=6\`, \`totalAmount=2100.0\` para una tienda sintética única y **1 evento** rechazado por cantidad inválida. La consulta de métricas toma diferencias en **offsets de tópicos completos**, no eventos exclusivos de la demo: otros productores pueden afectar deltas; no confundirlos con datos de la prueba.

## 4. Atajos de operación

Se ejecutan siempre desde la carpeta raíz del repositorio:

| Comando | Qué permite ver/hacer | Riesgo |
| --- | --- | --- |
| \`bash ep5/operar.sh ayuda\` | Lista oficial de comandos | Solo lectura |
| \`bash ep5/operar.sh estado\` | Estado de EC2, Streams, brokers y contenedores | Solo lectura |
| \`bash ep5/operar.sh kafka-ui\` | Abre túnel a Kafka UI | No modifica servidor |
| \`bash ep5/operar.sh grafana\` | Abre túnel privado de Grafana | No modifica servidor |
| \`bash ep5/operar.sh prometheus\` | Abre túnel privado a Prometheus | No modifica servidor |
| \`bash ep5/operar.sh topicos\` | Lista/descripción de tópicos y ISR | Solo lectura |
| \`bash ep5/operar.sh grupos\` | Grupo consumidor de Streams, offsets/lag | Solo lectura |
| \`bash ep5/operar.sh configs\` | Abre configuración versionada en Kate | Solo lectura |
| \`bash ep5/operar.sh configs-vivas\` | Consulta configuración real desplegada | Solo lectura; filtra secretos |
| \`bash ep5/operar.sh ssh-app\` | SSH interactivo en APP | Administrador; cautela |
| \`bash ep5/operar.sh ssh-kafka1\` | SSH interactivo en Kafka-1 | Administrador; cautela |
| \`bash ep5/operar.sh ssh-kafka2\` | SSH interactivo en Kafka-2 | Administrador; cautela |
| \`bash ep5/operar.sh ssh-monitoring\` | SSH interactivo en Monitoring | Administrador; cautela |
| \`bash ep5/operar.sh prueba demo\` | Inyecta 8 mensajes sintéticos y verifica el flujo real | Agrega registros Kafka |
| \`bash ep5/operar.sh prueba tardios\` | Ejecuta pruebas Maven TopologyTestDriver | Cambia archivo de test en APP; no reinicia Streams |
| \`bash ep5/operar.sh prueba estado\` | Audita métricas reales y targets Prometheus | Solo lectura |
| \`bash ep5/operar.sh prueba persistencia\` | Reinicia el servicio de Kafka Streams y verifica recuperación | **Disruptivo** |
| \`bash ep5/operar.sh prueba failover\` | Detiene Kafka-2, verifica el failover y lo recupera | **Disruptivo** |
| \`bash ep5/operar.sh prueba postboot\` | Reinicia EC2 Monitoring y verifica recuperación | **Disruptivo** |
| \`bash ep5/operar.sh ultimo\` | Abre el último informe TXT de DSY1107 en Kate | Solo lectura |

Para las tres pruebas disruptivas se exige confirmar una palabra en la terminal. **No ejecutar simultáneamente \`failover\`, \`persistencia\` y \`postboot\`.** En una evaluación en vivo comenzar siempre por la demo no disruptiva.

## 5. Qué archivo de configuración corresponde a cada parte

Abre todos los archivos versionados en Kate con:

\`\`\`bash
bash ep5/operar.sh configs
\`\`\`

**APP / Streams:**

- \`ep5/app/streams/.env.example\`: define application ID, bootstrap servers y state dir esperados; **la configuración activa está en APP** en \`/home/ubuntu/dsy1107-ep5/streams/.env\`.
- \`ep5/app/streams/deploy/dsy1107-ventas-streams.service\`: archivo systemd, define User, WorkingDirectory, variables EnvironmentFile, Java 21, límite JVM 512 MiB, Restart=on-failure.
- \`ep5/app/streams/src/main/java/cl/duoc/dsy1107/streams/VentasStreams.java\`: procesador principal; valida JSON, deduplica por eventId en RocksDB, ventanas de 1 min con 30 s de gracia, produce agregaciones y DLQ.
- \`ep5/app/streams/pom.xml\`: dependencias y compilación Maven.

**Monitoring:**

- \`ep5/monitoring/compose.yaml\`: tres contenedores, límites de memoria, redes, bind a localhost y política restart.
- \`ep5/monitoring/prometheus/prometheus.yml\`: scrape interval de 15 s, jobs \`prometheus\` y \`kafka-exporter\`; Kafka Exporter recibe conexiones hacia 172.31.91.91:9092 y 172.31.27.158:9092.
- \`ep5/monitoring/grafana/provisioning/datasources/prometheus.yaml\`: fuente de datos provisionada para Grafana.
- \`ep5/monitoring/grafana/provisioning/dashboards/default.yaml\`: carpeta y mecanismo de provisión del dashboard.
- \`ep5/monitoring/grafana/dashboards/dsy1107-kafka-ep5.json\`: definición de los 15 paneles, consultas PromQL y umbrales visuales.

**Kafka / brokers:**

La configuración real del broker se verifica con las variables de entorno del contenedor y la descripción de los tópicos. No hay un archivo Kafka broker \`server.properties\` versionado en la carpeta EP5 para abrir localmente. El comando \`configs-vivas\` consulta datos concretos de los contenedores desplegados, sin emitir credenciales.

### Comparar configuración versionada versus configuración desplegada

\`\`\`bash
bash ep5/operar.sh configs-vivas
\`\`\`

Esto lee el \`systemd\` de APP, algunas variables \`KAFKA_*\` permitidas, parámetros no sensibles de ambos brokers y el \`prometheus.yml\` realmente instalado en Monitoring. Es la forma correcta de contestar «¿dónde se configura este servicio?» sin inventar rutas o imprimir contraseñas.

## 6. Comandos directos útiles dentro de una sesión SSH

Primero conectarse desde Ryzen:

\`\`\`bash
bash ep5/operar.sh ssh-app
\`\`\`

**Una vez DENTRO de APP**, los comandos típicos son:

\`\`\`bash
systemctl status dsy1107-ventas-streams.service --no-pager
sudo journalctl -u dsy1107-ventas-streams.service -n 50 --no-pager
systemctl show dsy1107-ventas-streams.service -p ExecStart -p Restart -p EnvironmentFiles
\`\`\`

Cerrar con \`exit\`.

Para abrir un broker desde Ryzen:

\`\`\`bash
bash ep5/operar.sh ssh-kafka2
\`\`\`

**Dentro de Kafka-2**:

\`\`\`bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo docker exec dsy1107-broker-2 kafka-topics \
  --bootstrap-server localhost:9092 --describe --topic ventas-raw
sudo docker exec dsy1107-broker-2 kafka-consumer-groups \
  --bootstrap-server localhost:9092 --describe --group dsy1107-ventas-streams
\`\`\`

Para Monitoring:

\`\`\`bash
bash ep5/operar.sh ssh-monitoring
\`\`\`

**Dentro de Monitoring**:

\`\`\`bash
cd /home/ubuntu/dsy1107-ep5/monitoring
sudo docker compose ps
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:3000/api/health
cat prometheus/prometheus.yml
\`\`\`

No ejecutar \`docker compose down -v\`, \`docker system prune --volumes\`, ni borrar directorios de estado Kafka durante una evaluación.

## 7. Procedimiento recomendado para una prueba en vivo

1. Activar sesión AWS Academy, verificar EC2 con \`estado\`.
2. Abrir tres terminales de túneles: Kafka UI, Grafana y Prometheus (opcional).
3. En Firefox revisar brokers, tópicos e ISR antes de publicar nada.
4. Ejecutar \`topicos\` y \`grupos\` desde una cuarta terminal.
5. Ejecutar **solo** \`prueba demo\` y leer su TXT.
6. Volver a Kafka UI: localizar la tienda \`DEMO-EP5-...\`, su agregado y el mensaje DLQ.
7. Volver a Grafana: revisar actividad de los tópicos, lag del grupo y estado de ISR. Prometheus puede tardar varios intervalos de 15 s en reflejar los cambios.
8. Si la persona evaluadora pide configuraciones, abrir \`configs\` y comparar con \`configs-vivas\`.
9. Mostrar la prueba de failover/persistencia ya certificada si no es necesario provocar cortes en vivo. Ejecutarlas solo cuando corresponda y con permiso del grupo/docente.

### Evidencias logradas al 21-nov-2026

- Validaciones Kafka Streams: 4 tests Maven, sin fallos.
- Procesamiento E2E: validación, agregación, DLQ y deduplicación real.
- Failover Kafka-2: escritura/lectura en Kafka-1 y retorno de ISR a 2/2.
- Persistencia Streams: deduplicación y agregación tras reinicio.
- Monitoring: 3 contenedores, 15 paneles, 15 consultas PromQL, 2 brokers detectados.
- Reinicio completo de Monitoring: \`boot_id\` nuevo, Docker/containers/targets/paneles recuperados.
- Demo integral: 8 eventos raw, 6 ventas válidas, 1 duplicado, 1 inválido, total 2100.0. Incrementos en offsets: +8 raw, +7 agregadas, +2 DLQ; los offsets son del tópico entero, no una traza individual.

**Importante:** los estados certificados se refieren a las pruebas realizadas en esas fechas. Para afirmar que siguen operativos el día de la evaluación, volver a ejecutar \`estado\`, \`topicos\` y \`prueba estado\`.

## 8. Diagnóstico rápido

| Síntoma | Qué comprobar primero |
| --- | --- |
| Kafka UI no abre | ¿La terminal de \`kafka-ui\` sigue abierta? ¿APP tiene IP pública y Kafka-1 está activo? |
| Grafana no abre | ¿El túnel \`grafana\` está abierto? ¿Hay otro proceso en 3000 del Ryzen? |
| Prometheus no abre | Abrir \`prometheus\`; usar puerto local **19090** en lugar de 9090 |
| AWS CLI falla | Sesión AWS Academy activa, perfil \`pedidos360\`, permisos y región \`us-east-1\` |
| Los brokers muestran 1/2 ISR | Ejecutar \`topicos\` y comprobar broker 2; no repetir failover hasta recuperarlo |
| Grafana muestra «No data» | Ejecutar \`prueba estado\` y ver targets; confirmar que hay datos desde que comenzó la captura |
| Lag igual a -1 | Indica offset no confirmado/desconocido, no un atraso medible: no sumarlo como positivo |
| Script sale con error | Abrir último TXT con \`ultimo\`, localizar el primer \`ERROR\` y revisar estado antes de reejecutar |

## 9. Recuperación del material y conservación

- **Fuente versionada:** GitHub \`krockzs/Evaluacion1-DSY1107\`, rama \`ep5-app\`.
- **Scripts:** \`ep5/tests/\` y \`ep5/monitoring/\`.
- **Guía y atajos:** \`ep5/GUIA_OPERATIVA_CLASE.md\` y \`ep5/operar.sh\`.
- **Informes TXT:** \`/tmp/DSY1107_*.txt\` del Ryzen. **La carpeta /tmp no es persistente** tras limpieza/reinicio del Ryzen: copiar las evidencias finales a un directorio de respaldos fuera de /tmp si se necesitan para defensa.
- **No subir secretos:** PEM, configuración activa \`.env\` si contiene secretos, archivos \`secrets/\`, contraseñas y tokens.

**Criterio operativo:** primero comprobar la infraestructura; segundo abrir UI; tercero ejecutar demo segura; cuarto enseñar los datos; quinto mostrar las configuraciones relevantes. Entender qué servicio se inspecciona y dónde está desplegado es más útil que memorizar comandos sueltos.
