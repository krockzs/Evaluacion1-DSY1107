# Evaluación 1 — DSY1107 Desarrollo Cloud Native I

Proyecto académico desarrollado para la **Evaluación Parcial N.º 1 de DSY1107 — Desarrollo Cloud Native I**.

La solución implementa un sistema de gestión de órdenes de trabajo para un taller, denominado **Pedidos360 / TallerPro360**, utilizando una arquitectura distribuida compuesta por frontend Angular, BFF, microservicios Spring Boot, mensajería asíncrona, base de datos Oracle, autenticación con Microsoft Entra ID y servicios desplegados en AWS.

---

## Objetivo del proyecto

El objetivo es implementar una solución cloud native capaz de:

- autenticar usuarios mediante **Microsoft Entra ID**;
- consumir una API protegida mediante **JWT**;
- utilizar **Amazon API Gateway** como punto de entrada público;
- centralizar el acceso del frontend mediante un **Backend for Frontend (BFF)**;
- separar responsabilidades en microservicios;
- persistir datos en **Oracle Database**;
- procesar eventos mediante **Apache Kafka**;
- procesar notificaciones mediante **RabbitMQ**;
- desplegar los componentes principales en **AWS**.

El flujo general es:

```text
Usuario
  |
  v
Angular + MSAL
  |
  | Bearer JWT
  v
Amazon API Gateway
  |
  | JWT Authorizer
  v
BFF Spring Boot
  |
  +------> OT Service
  |
  +------> Event Service
  |
  +------> Notification Service
                 |
                 v
              Oracle
```

Además:

```text
OT Service --Kafka------> Event Service
OT Service --RabbitMQ---> Notification Service
```

---

# Organización del repositorio

El proyecto se divide en **cuatro ramas principales**, cada una con una responsabilidad específica.

## `main`

Rama principal del proyecto.

Contiene la solución completa y representa la integración de todos los componentes:

```text
Evaluacion1/
├── backend/
│   ├── bff-service/
│   ├── ot-service/
│   ├── event-service/
│   └── notification-service/
├── frontend/
│   └── pedidos360-web/
├── Sql/
│   └── Script.sql
├── scripts/
└── README.md
```

Esta rama sirve como referencia global del sistema y reúne backend, frontend, base de datos y documentación.

---

## `app`

Rama destinada al backend de la aplicación.

Incluye:

- BFF;
- microservicio de órdenes de trabajo;
- microservicio de eventos;
- microservicio de notificaciones;
- configuración de Spring Security;
- integración con Oracle;
- integración con Kafka;
- integración con RabbitMQ;
- scripts auxiliares de ejecución.

Servicios incluidos:

| Servicio | Puerto | Responsabilidad |
|---|---:|---|
| BFF Service | 8080 | Punto de entrada del frontend y validación del JWT |
| OT Service | 8081 | Gestión de órdenes de trabajo e ítems |
| Event Service | 8082 | Consumo de eventos Kafka y persistencia |
| Notification Service | 8083 | Consumo de mensajes RabbitMQ y persistencia |

El backend fue desarrollado con **Java + Spring Boot**.

---

## `frontend`

Rama destinada exclusivamente al frontend.

Tecnologías principales:

- **Angular**
- **TypeScript**
- **MSAL**
- **Microsoft Entra ID**

El frontend permite:

- iniciar sesión;
- cerrar sesión;
- consumir la API protegida;
- listar órdenes de trabajo;
- crear órdenes;
- acceder a vistas protegidas mediante autenticación.

La autenticación se realiza utilizando **MSAL**, obteniendo un access token desde Microsoft Entra ID.

El frontend fue compilado para producción y publicado en Amazon S3.

---

## `db`

Rama destinada exclusivamente a la base de datos.

Contiene:

```text
Sql/Script.sql
```

La solución utiliza **Oracle Database Free**.

El script define las estructuras principales del modelo:

- `OT`
- `OT_ITEM`
- `OT_EVENT`
- `NOTIFY_LOG`
- `V_OT_RESUMEN`

Durante el despliegue en AWS se utilizó el esquema `SYSTEM` de Oracle Free para la ejecución académica del proyecto.

---

# Arquitectura backend

## BFF Service

El **Backend for Frontend** es el punto de comunicación entre Angular y los microservicios internos.

Responsabilidades:

- recibir solicitudes desde API Gateway;
- validar nuevamente el JWT;
- validar audiencia y emisor;
- aplicar configuración CORS;
- comunicarse con los microservicios internos;
- evitar que el frontend conozca directamente las direcciones internas de los servicios.

Aunque API Gateway valida el JWT en el borde, el BFF también realiza validación de seguridad como parte de los requisitos de la evaluación.

---

## OT Service

Microservicio principal del dominio.

Gestiona:

- órdenes de trabajo;
- ítems asociados;
- consultas de resumen;
- persistencia en Oracle;
- publicación de eventos en Kafka;
- publicación de notificaciones en RabbitMQ.

---

## Event Service

Microservicio encargado del procesamiento de eventos.

Consume mensajes publicados por OT Service mediante **Apache Kafka** y registra los eventos correspondientes en Oracle.

Puerto:

```text
8082
```

Kafka:

```text
9092
```

---

## Notification Service

Microservicio encargado de procesar notificaciones.

Consume mensajes enviados por OT Service mediante **RabbitMQ** y registra la información correspondiente en Oracle.

Puerto:

```text
8083
```

RabbitMQ:

```text
5672
```

---

# Base de datos

La base de datos utilizada es:

```text
Oracle Database Free
```

Puerto:

```text
1521
```

Servicio utilizado:

```text
FREEPDB1
```

La instancia Oracle fue desplegada en una instancia EC2 separada utilizando un contenedor **Podman**.

Esto permite separar:

```text
EC2 APP
```

de:

```text
EC2 DB
```

La aplicación se conecta a Oracle utilizando la IP privada de la instancia de base de datos dentro de la VPC.

---

# Mensajería

## Apache Kafka

Kafka se utiliza para el procesamiento asíncrono de eventos.

Flujo:

```text
OT Service
   |
   v
Kafka
   |
   v
Event Service
   |
   v
Oracle / OT_EVENT
```

Puerto:

```text
9092
```

---

## RabbitMQ

RabbitMQ se utiliza para el procesamiento de notificaciones.

Flujo:

```text
OT Service
   |
   v
RabbitMQ
   |
   v
Notification Service
   |
   v
Oracle / NOTIFY_LOG
```

Puerto:

```text
5672
```

---

# Microsoft Entra ID

La autenticación fue implementada mediante **Microsoft Entra ID**.

Se crearon dos aplicaciones:

```text
Pedidos360-SPA
```

y:

```text
Pedidos360-API
```

`Pedidos360-SPA` representa el frontend Angular.

`Pedidos360-API` representa la API protegida.

La API expone los scopes:

```text
ot.read
ot.write
```

Los access tokens utilizados por la solución corresponden a tokens **v2.0** de Microsoft Entra ID.

Flujo de autenticación:

```text
Angular
  |
  v
Microsoft Entra ID
  |
  | access token
  v
Angular
  |
  | Authorization: Bearer <JWT>
  v
Amazon API Gateway
```

---

# AWS

La solución fue desplegada utilizando servicios de **AWS Academy**.

Los componentes principales utilizados son:

- Amazon EC2
- Amazon API Gateway
- Amazon S3
- Security Groups
- VPC
- Microsoft Entra ID como proveedor de identidad externo

---

## EC2 APP

Instancia destinada a ejecutar:

- BFF Service;
- OT Service;
- Event Service;
- Notification Service;
- Apache Kafka;
- RabbitMQ.

Puertos principales:

| Componente | Puerto |
|---|---:|
| BFF | 8080 |
| OT Service | 8081 |
| Event Service | 8082 |
| Notification Service | 8083 |
| Kafka | 9092 |
| RabbitMQ | 5672 |

---

## EC2 DB

Instancia destinada a ejecutar Oracle Database Free.

Oracle se ejecuta mediante Podman.

Puerto:

```text
1521
```

La comunicación entre APP y DB se realiza dentro de la red privada de AWS.

---

# Amazon API Gateway

Se creó una API HTTP denominada:

```text
Pedidos360-API
```

API Gateway se utiliza como entrada pública al backend.

Rutas principales:

```text
ANY /
ANY /{proxy+}
OPTIONS /{proxy+}
```

Las rutas `ANY` utilizan un **JWT Authorizer** conectado con Microsoft Entra ID.

La ruta `OPTIONS` se mantiene sin autenticación para permitir correctamente las solicitudes CORS del navegador.

También se configuró un parameter mapping para conservar la ruta original:

```text
overwrite:path = $request.path
```

Esto permite que una solicitud como:

```text
/api/ots
```

llegue al BFF manteniendo exactamente esa misma ruta.

---

# Amazon S3

El frontend Angular se compila en modo producción y se publica en un bucket S3.

La aplicación utiliza hash routing, por lo que las rutas del frontend tienen la forma:

```text
index.html#/ots
```

S3 actúa como alojamiento del frontend estático.

---

# Seguridad

El flujo de seguridad implementado es:

```text
Usuario
  |
  v
Microsoft Entra ID
  |
  v
Angular + MSAL
  |
  | JWT
  v
Amazon API Gateway
  |
  | JWT Authorizer
  v
BFF Spring Security
  |
  v
Microservicios
```

Existe validación en dos niveles:

1. API Gateway valida el JWT antes de permitir el acceso al backend.
2. El BFF vuelve a validar el token mediante Spring Security.

Se utilizan scopes:

```text
ot.read
ot.write
```

para controlar el acceso a los recursos protegidos.

---

# CORS

El backend permite solicitudes provenientes del frontend desplegado en S3.

El BFF utiliza una configuración centralizada de Spring Security y CORS.

API Gateway también posee configuración CORS para permitir:

```text
Authorization
Content-Type
```

y métodos:

```text
GET
POST
PUT
PATCH
DELETE
OPTIONS
```

---

# Puertos utilizados

| Componente | Puerto |
|---|---:|
| Angular local | 4200 |
| BFF | 8080 |
| OT Service | 8081 |
| Event Service | 8082 |
| Notification Service | 8083 |
| Oracle | 1521 |
| Kafka | 9092 |
| RabbitMQ | 5672 |

---

# Flujo funcional completo

```text
1. El usuario abre Angular desde Amazon S3.

2. Angular solicita autenticación mediante Microsoft Entra ID.

3. Entra ID entrega un access token JWT.

4. Angular envía el token a Amazon API Gateway.

5. API Gateway valida:
   - issuer
   - audience
   - scopes

6. API Gateway reenvía la solicitud al BFF.

7. El BFF valida nuevamente el JWT.

8. El BFF envía la solicitud al microservicio correspondiente.

9. OT Service consulta o modifica Oracle.

10. Cuando corresponde:
    - publica eventos en Kafka;
    - publica notificaciones en RabbitMQ.

11. Event Service consume Kafka.

12. Notification Service consume RabbitMQ.

13. Los resultados quedan persistidos en Oracle.
```

---

# Tecnologías utilizadas

## Frontend

- Angular
- TypeScript
- HTML
- CSS
- MSAL

## Backend

- Java
- Spring Boot
- Spring Security
- Spring Data JPA
- Maven

## Base de datos

- Oracle Database Free
- SQL

## Mensajería

- Apache Kafka
- RabbitMQ

## Cloud

- AWS EC2
- AWS API Gateway
- AWS S3
- AWS Security Groups
- AWS VPC

## Identidad

- Microsoft Entra ID
- OAuth 2.0
- OpenID Connect
- JWT

## Infraestructura del sistema

- Ubuntu Server
- Podman
- Git
- GitHub

---

# Propósito académico

Este repositorio corresponde a una implementación realizada para demostrar conocimientos de:

- desarrollo cloud native;
- arquitectura distribuida;
- microservicios;
- autenticación y autorización;
- integración con servicios cloud;
- mensajería asíncrona;
- persistencia de datos;
- frontend SPA;
- despliegue en AWS.

La solución fue implementada y desplegada funcionalmente en AWS Academy, integrando frontend, autenticación, API Gateway, backend, microservicios, mensajería y base de datos.

---

# Estado del proyecto

La integración funcional implementada contempla:

```text
Angular
Microsoft Entra ID
Amazon S3
Amazon API Gateway
BFF
OT Service
Event Service
Notification Service
Apache Kafka
RabbitMQ
Oracle Database Free
```

El proyecto se organiza mediante las ramas:

```text
main
app
frontend
db
```

donde `main` representa la visión completa de la solución y las demás ramas separan las responsabilidades principales del sistema.
