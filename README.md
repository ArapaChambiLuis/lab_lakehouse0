# Construye un Lakehouse escalable en AWS como lo pide hoy el mercado laboral

Workshop nivel 200 · AWS Community Day · Caso: **Aseguradora Andina S.A.** (empresa y datos ficticios)

Pasamos de CSVs sueltos de pólizas y siniestros a un Lakehouse con capas Bronze, Silver y Gold sobre **Amazon S3 Tables (Apache Iceberg)**, procesado con **AWS Glue 5.0** y consultado con **Amazon Athena**. Incluye time travel para auditoría.

```
 CSV crudos ──► S3 (Bronze) ──► Glue 5.0 / PySpark ──► S3 Tables · Iceberg (Silver) ──► Glue ──► S3 Tables (Gold)
                    │                                          │                                     │
                    └──────────────── Athena (SQL) ◄───────────┴─────────────────────────────────────┘
```

## 🚀 Despliegue en un comando

La forma más fácil es **AWS CloudShell** (botón `>_` arriba a la derecha en la consola de AWS). Ya trae la AWS CLI y Python, y no tiene costo.

```bash
git clone <URL-de-este-repo> && cd lakehouse-aseguradora-aws
./deploy.sh
```

En ~10–12 minutos tienes todo listo, con los resultados impresos en pantalla.

| Opción | Para qué |
|---|---|
| `./deploy.sh` | Todo: infraestructura, Bronze, Silver, Gold y Lab 4 |
| `./deploy.sh --hasta infra` | Solo la infraestructura (para hacer los labs a mano) |
| `./deploy.sh --hasta silver` | **Rescate**: te deja listo para empezar el Lab 3 |
| `./deploy.sh --email tu@correo.com` | Agrega una alerta de presupuesto de 5 USD |
| `./deploy.sh --region us-west-2` | Otra región (por defecto `us-east-1`) |
| `./deploy.sh --entorno dev` | Otro entorno: crea `lkh-dev-*` sin tocar `lkh-lab-*` |
| `./deploy.sh --owner luis --proyecto lkh` | Personaliza los tags y el código de proyecto |

Etapas de `--hasta`: `infra` → `bronze` → `silver` → `gold` → `lab4`. Puedes ejecutar el script las veces que quieras: es idempotente.

## 👣 Lab por lab (modo workshop)

```bash
./lab.sh 0 --email tu@correo.com   # infraestructura
./lab.sh 1                          # Bronze
./lab.sh 2                          # Silver
./lab.sh 3                          # Gold
./lab.sh 4                          # Auditoría y time travel
```

Cada lab tiene su guía paso a paso en [`labs/`](labs/README.md). Si intentas un lab sin haber hecho el anterior, `lab.sh` te avisa y te dice cómo ponerte al día.

## 🖱️ Sin terminal: manual por consola

¿Quieres entender qué hace cada pieza, o no puedes usar la terminal? El [manual paso a paso por la consola de AWS](labs/manual-consola/README.md) construye el mismo Lakehouse a mano: bucket, table bucket, rol IAM, jobs de Glue, workgroup de Athena, los labs 1 a 4 y la limpieza, con los mismos nombres y tags del estándar.

## 🧹 Limpieza (no te lo saltes)

```bash
./cleanup.sh          # pide confirmacion; --si para no preguntar
```

En 5 pasos: tablas Iceberg de `silver` y `gold` → base `lkh_lab_bronze` del Data Catalog →
contenido del bucket raw (incluidas las subidas multiparte a medias, que si no bloquean el
borrado) → retención de 7 días en los log groups de Glue → `delete-stack` (bucket, table
bucket, jobs, rol IAM, workgroup y presupuesto).

Si ya borraste el stack desde la consola, igual puedes correrlo: entra en **modo huérfanos**,
deduce los nombres del estándar y limpia lo que haya quedado suelto.

Lo único que se conserva a propósito es el catálogo `s3tablescatalog` de Glue: es compartido por
toda la cuenta y región, no cobra, y borrarlo rompería otros table buckets. Si lo quieres fuera:
`aws glue delete-catalog --catalog-id s3tablescatalog`.

## 📦 Qué se crea

| Recurso | Nombre | Capa |
|---|---|---|
| Stack de CloudFormation | `lkh-lab-stack` | |
| Bucket S3 | `lkh-lab-raw-<cuenta>-<region>` | Bronze, scripts y resultados de Athena |
| Table bucket (S3 Tables) | `lkh-lab-tables` | Silver y Gold |
| Namespaces | `silver`, `gold` | |
| Jobs de Glue 5.0 | `lkh-lab-job-bronze-to-silver`, `lkh-lab-job-silver-to-gold`, `lkh-lab-job-silver-auditoria` | 2 workers G.1X cada uno |
| Workgroup de Athena | `lkh-lab-wg-analistas` | Límite de 1 GB escaneado por consulta |
| Base del Glue Data Catalog | `lkh_lab_bronze` | Tablas externas sobre los CSV |
| Rol IAM | `lkh-lab-role-glue-<region>` | Acceso mínimo al bucket y al table bucket |
| Presupuesto (opcional) | `lkh-lab-budget-5usd` | Alerta al 50% de 5 USD |

## 🏷️ Nomenclatura y tags

El repo sigue un estándar de nombres como el que pide un área de arquitectura en banca y seguros. Con solo leer el nombre sabes **qué es, de qué entorno es y qué hace**.

| Tipo | Patrón | Separador | Ejemplo |
|---|---|---|---|
| Recursos AWS | `{proyecto}-{entorno}-{componente}[-{detalle}]` | guion medio | `lkh-lab-tables` |
| Jobs de Glue | `{proyecto}-{entorno}-job-{origen}-to-{destino}` | guion medio | `lkh-lab-job-bronze-to-silver` |
| Recursos globales | se agrega `{cuenta}-{region}` o `{region}` | guion medio | `lkh-lab-raw-123456789012-us-east-1` |
| Bases de datos | `{proyecto}_{entorno}_{capa}` | guion bajo | `lkh_lab_bronze` |
| Tablas Bronze/Silver | `{entidad}` en plural | guion bajo | `pagos_primas` |
| Tablas Gold | `{tipo}_{tema}_{granularidad}` (`agg_` = agregada) | guion bajo | `agg_siniestralidad_producto_anual` |
| Scripts de Glue | igual que su job | guion bajo | `bronze_to_silver.py` |

**¿Por qué dos separadores?** S3, IAM y Glue Jobs aceptan guiones, pero las bases de datos de Glue y Athena no. Regla: **guion medio para recursos, guion bajo para objetos de datos**.

**Columnas:** `id_` identificador · `fecha_` fecha · `monto_` importe · `n_` conteo · `ratio_` proporción · `flag_`/`dato_` booleano. Los códigos van en MAYÚSCULAS (`PAGADO`, `SALUD`) y los ids de negocio como `{ENTIDAD}-{número}` (`SIN-00042`).

**Tags:** todo el stack lleva estos tags, aplicados por `deploy.sh`:

| Tag | Valor por defecto | Para qué |
|---|---|---|
| `Proyecto` | `lakehouse-aseguradora` | Agrupar todo el proyecto |
| `Entorno` | `lab` | Separar lab/dev/qa/prd |
| `Owner` | tu usuario de AWS (`--owner`) | Saber a quién preguntar |
| `CentroCosto` | `workshop-awscd` | Filtrar costos en Cost Explorer |
| `Clasificacion` | `confidencial` (bucket raw y table bucket, porque tienen PII) | Marcar dónde hay datos sensibles |

Cada tabla Iceberg también lleva la propiedad `clasificacion`: `confidencial` en `silver.clientes` e `interna` en el resto. Puedes verla con `SHOW TBLPROPERTIES`.

> Tip FinOps: para que Cost Explorer filtre por estos tags, actívalos una vez en *Billing → Cost allocation tags*.

## 🧪 Los labs

| Lab | Qué haces | Código | Guía |
|---|---|---|---|
| 0 · Setup | Infraestructura como código y alerta de costos | `infra/template.yaml` | [lab0](labs/lab0-setup/README.md) |
| 1 · Bronze | Subir los CSV crudos y ver la "suciedad" con Athena | `sql/bronze_ddl.sql` | [lab1](labs/lab1-bronze/README.md) |
| 2 · Silver | Deduplicar, tipar, normalizar e integridad referencial → Iceberg | `glue/bronze_to_silver.py` | [lab2](labs/lab2-silver/README.md) |
| 3 · Gold | Siniestralidad por producto, evolución mensual y cartera sin PII | `glue/silver_to_gold.py` | [lab3](labs/lab3-gold/README.md) |
| 4 · Auditoría | Agregar una columna, corregir el siniestro `SIN-00042` y time travel | `glue/silver_auditoria.py` | [lab4](labs/lab4-auditoria/README.md) |
| 5 · Gobierno | Permisos por columna con Lake Formation (demo) | — | [lab5](labs/lab5-gobierno/README.md) |

Las consultas para la consola de Athena están en `sql/consultas_workshop.sql`. Para Silver y Gold, elige el catálogo **`s3tablescatalog/lkh-lab-tables`**.

### Lab 5 · Gobierno (demo)
El despliegue usa la integración de S3 Tables con **control de acceso por IAM**, que es la opción por defecto y la más simple para un lab. Los permisos por columna requieren activar Lake Formation sobre `s3tablescatalog`, y eso cambia la configuración de toda la cuenta. Por eso se muestra como demo en vivo y no se automatiza. Mientras tanto, Gold ya aplica el principio: `gold.agg_cartera_region_producto` no contiene DNI, nombre ni email.

## 💲 Costos

Con los datos del lab (~2 MB), una ejecución completa cuesta **menos de 1 USD**. La mayor parte se va en los 3 jobs de Glue de pocos minutos cada uno. Athena escanea solo KB, y en S3 Tables se almacenan pocos MB.

- Cuentas creadas desde el 15/07/2025: lo cubren los créditos de la capa gratuita.
- Cuentas más antiguas: pagan esos centavos de verdad.
- Las cuentas que pertenecen a una AWS Organization no reciben créditos de capa gratuita.

## 🛠️ Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| `aws: s3tables is not a valid choice` | CLI antigua. Usa CloudShell o actualiza la AWS CLI v2 |
| Athena no ve `silver`/`gold` | Tu cuenta ya tenía la integración antigua de S3 Tables con Lake Formation. Date permisos en Lake Formation sobre `s3tablescatalog/lkh-lab-tables` o rehaz la integración (guía oficial de S3 Tables) |
| Falla el DDL de Bronze con `Insufficient Lake Formation permissions` | Tu cuenta tiene Lake Formation con permisos estrictos. Usa una cuenta de laboratorio o hazte administrador del data lake |
| El job de Glue falla | Revisa en CloudWatch `/aws-glue/jobs/error` o `/aws-glue/jobs/output` |
| `Malformed request: Stage-create is currently not supported` | S3 Tables no soporta el *staged create*. El `SparkCatalog` de Iceberg implementa `StagingTableCatalog`, así que Spark enruta **todo CTAS** (`writeTo().create()`, `.createOrReplace()`, `CREATE TABLE ... AS SELECT`) por el plan atómico que lo pide. Los jobs usan `CREATE TABLE` con esquema explícito + `append()`, que no pasa por staging. Si te sale, tu copia en `s3://<bucket>/scripts/` está vieja: `./lab.sh 2` la vuelve a subir antes de lanzar el job |
| `AlreadyExists` en un recurso | Ya hay un despliegue con esos nombres. Usa otro entorno o proyecto: `./deploy.sh --entorno dev` |

## 💼 Llévalo a tu CV

> Diseñé e implementé un Lakehouse en AWS (S3 Tables/Apache Iceberg, Glue 5.0, Athena) con arquitectura medallion para datos de seguros. Incluye control de calidad, evolución de esquema, time travel para auditoría e infraestructura como código con CloudFormation.

---
Datos 100% sintéticos, generados por `data/generator.py`. Cualquier parecido con una persona real es coincidencia.
