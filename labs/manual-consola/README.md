# Manual paso a paso por la consola de AWS

Este manual construye **el mismo Lakehouse** que `./deploy.sh`, pero a mano, clic por clic, en la consola de AWS. Sirve para:

- **Entender qué automatiza el script.** Cada paso de aquí es una línea de `infra/template.yaml` o de `scripts/etapas.sh`.
- **Hacer el workshop sin terminal.**
- **Aprender dónde está cada cosa** en la consola: es lo que vas a usar en el día a día.

⏱️ **Tiempo:** 60–90 minutos la primera vez · 💲 **Costo:** menos de 1 USD si haces la limpieza al final.

> Las pantallas de AWS cambian de vez en cuando. Si un botón tiene otro nombre, busca la opción equivalente: los conceptos son los mismos.

---

## Índice

| Parte | Qué haces | Equivale a |
|---|---|---|
| [0. Preparación](#0-preparación) | Región, ID de cuenta y archivos del repo | — |
| [1. Alerta de costos](#1-alerta-de-costos-aws-budgets) | Presupuesto de 5 USD | `Presupuesto` en el template |
| [2. Bucket S3 (Bronze)](#2-bucket-s3-para-bronze-scripts-y-athena) | Bucket, reglas de ciclo de vida, CSV y scripts | `RawBucket` + Lab 1 |
| [3. Table bucket (Silver y Gold)](#3-table-bucket-de-s3-tables-silver-y-gold) | S3 Tables, integración y namespaces | `TableBucket` + namespaces |
| [4. Rol IAM](#4-rol-iam-para-glue) | Permisos mínimos para Glue | `GlueRole` |
| [5. Jobs de Glue](#5-jobs-de-glue) | Los 3 jobs de PySpark | `JobBronzeToSilver`, etc. |
| [6. Workgroup de Athena](#6-workgroup-de-athena) | Workgroup con tope de 1 GB | `AthenaWorkGroup` |
| [7. Lab 1 · Bronze](#7-lab-1--bronze-tablas-en-athena) | Tablas externas sobre los CSV | `./lab.sh 1` |
| [8. Lab 2 · Silver](#8-lab-2--silver) | Correr el job y verificar | `./lab.sh 2` |
| [9. Lab 3 · Gold](#9-lab-3--gold) | Correr el job y ver los KPIs | `./lab.sh 3` |
| [10. Lab 4 · Auditoría](#10-lab-4--auditoría-y-time-travel) | Corrección y time travel | `./lab.sh 4` |
| [11. Limpieza](#11-limpieza-manual) | Borrar todo en orden | `./cleanup.sh` |

---

## Nombres que vas a usar

Todo sigue el estándar del repo (sección *Nomenclatura y tags* del README principal). Reemplaza `<CUENTA>` por tu ID de cuenta de 12 dígitos.

| Recurso | Nombre |
|---|---|
| Bucket S3 | `lkh-lab-raw-<CUENTA>-us-east-1` |
| Table bucket | `lkh-lab-tables` |
| Namespaces | `silver`, `gold` |
| Rol IAM | `lkh-lab-role-glue-us-east-1` |
| Jobs de Glue | `lkh-lab-job-bronze-to-silver`, `lkh-lab-job-silver-to-gold`, `lkh-lab-job-silver-auditoria` |
| Workgroup de Athena | `lkh-lab-wg-analistas` |
| Base de Bronze | `lkh_lab_bronze` |
| Presupuesto | `lkh-lab-budget-5usd` |

**Tags para cada recurso que los acepte:**

| Key | Value |
|---|---|
| `Proyecto` | `lakehouse-aseguradora` |
| `Entorno` | `lab` |
| `Owner` | tu usuario o correo |
| `CentroCosto` | `workshop-awscd` |

> 💡 El bucket S3 y el table bucket llevan además `Clasificacion` = `confidencial`, porque guardan PII.

---

## 0. Preparación

1. Entra a la consola de AWS y, arriba a la derecha, elige la región **US East (N. Virginia) us-east-1**. Todo el manual se hace en esta región.
2. Copia tu **ID de cuenta**: haz clic en tu nombre de usuario (arriba a la derecha) y copia el número de 12 dígitos. Lo vas a pegar varias veces.
3. Descarga el repo: en GitHub, **Code → Download ZIP**, y descomprímelo. Vas a usar:
   - `data/sample/*.csv`: los 4 archivos de datos.
   - `glue/*.py`: los 3 scripts de los jobs.
   - `sql/bronze_ddl.sql` y `sql/consultas_workshop.sql`.

> ¿No están los CSV en `data/sample/`? Genéralos con `python3 data/generator.py`, o abre **CloudShell** (ícono `>_` arriba a la derecha), clona el repo y córrelo ahí.

---

## 1. Alerta de costos (AWS Budgets)

1. Busca **Billing and Cost Management** → menú izquierdo **Budgets** → **Create budget**.
2. Elige **Customize (advanced)** → **Cost budget** → **Next**.
3. Configura:
   - **Budget name:** `lkh-lab-budget-5usd`
   - **Period:** Monthly · **Budget renewal type:** Recurring budget
   - **Budgeting method:** Fixed · **Enter your budgeted amount:** `5`
4. **Next** → **Add an alert threshold**:
   - **Threshold:** `50` · **% of budgeted amount** · **Trigger:** Actual
   - **Email recipients:** tu correo
5. **Next** → **Create budget**.
6. Revisa tu correo y **confirma la suscripción** si AWS te lo pide.

✅ Te llegará un correo si el gasto real del mes pasa de 2.50 USD.

---

## 2. Bucket S3 para Bronze, scripts y Athena

### 2.1 Crear el bucket

1. Ve a **S3** → **General purpose buckets** → **Create bucket**.
2. **Bucket name:** `lkh-lab-raw-<CUENTA>-us-east-1`. Los nombres de bucket son únicos en todo el mundo: por eso lleva tu cuenta y la región.
3. **Block Public Access settings:** deja marcado **Block all public access**.
4. **Default encryption:** **SSE-S3** (viene por defecto).
5. **Tags:** agrega los 4 tags de la tabla, más `Clasificacion` = `confidencial` y `Capa` = `bronze`.
6. **Create bucket**.

### 2.2 Reglas de ciclo de vida

Entra al bucket → pestaña **Management** → **Create lifecycle rule**. Crea dos reglas:

| Regla | Configuración |
|---|---|
| `limpiar-resultados-athena` | **Limit the scope** con prefijo `athena-results/` → marca **Expire current versions of objects** → `7` días |
| `abortar-multipart-incompletos` | **Apply to all objects in the bucket** (confirma la advertencia) → marca **Delete expired object delete markers or incomplete multipart uploads** → **Delete incomplete multipart uploads** → `1` día |

> 🔍 ¿Por qué la segunda? Una subida multiparte a medias no aparece como objeto, pero cobra almacenamiento e impide borrar el bucket.

### 2.3 Subir los datos (Lab 1 · Bronze)

Crea estas carpetas con **Create folder** y sube a cada una su archivo con **Upload**:

| Carpeta | Archivo |
|---|---|
| `bronze/clientes/` | `data/sample/clientes.csv` |
| `bronze/polizas/` | `data/sample/polizas.csv` |
| `bronze/pagos_primas/` | `data/sample/pagos_primas.csv` |
| `bronze/siniestros/` | `data/sample/siniestros.csv` |

> ⚠️ Cada CSV va **en su propia carpeta**. Athena lee una tabla como "todos los archivos de una carpeta": si mezclas archivos, se mezclan las tablas.

### 2.4 Subir los scripts de Glue

Crea la carpeta `scripts/` y sube los 3 archivos de `glue/`:
`bronze_to_silver.py`, `silver_to_gold.py` y `silver_auditoria.py`.

✅ Tu bucket debe verse así:

```
lkh-lab-raw-<CUENTA>-us-east-1/
├── bronze/
│   ├── clientes/clientes.csv
│   ├── pagos_primas/pagos_primas.csv
│   ├── polizas/polizas.csv
│   └── siniestros/siniestros.csv
└── scripts/
    ├── bronze_to_silver.py
    ├── silver_auditoria.py
    └── silver_to_gold.py
```

---

## 3. Table bucket de S3 Tables (Silver y Gold)

### 3.1 Crear el table bucket

1. En **S3**, menú izquierdo → **Table buckets** → **Create table bucket**.
2. **Table bucket name:** `lkh-lab-tables`.
3. **Integration with AWS analytics services:** si aparece la opción, marca **Enable integration**. Esto crea el catálogo `s3tablescatalog` en Glue Data Catalog, que es lo que le permite a Athena ver tus tablas Iceberg. Se activa **una sola vez por cuenta y región**: si dice que ya está activada, sigue de largo.
4. Si la consola ofrece **Tags**, agrega los 4 tags más `Clasificacion` = `confidencial`.
5. **Create table bucket**.
6. Entra al table bucket y copia su **ARN**. Tiene esta forma:
   `arn:aws:s3tables:us-east-1:<CUENTA>:bucket/lkh-lab-tables`

### 3.2 Crear los namespaces `silver` y `gold`

Un namespace es como una "base de datos" dentro del table bucket.

**Opción A, consola:** dentro de `lkh-lab-tables`, si ves **Create namespace**, crea `silver` y luego `gold`.

**Opción B, CloudShell:** si tu consola no tiene ese botón, abre **CloudShell** (`>_`) y pega esto, reemplazando `<CUENTA>`:

```bash
ARN=arn:aws:s3tables:us-east-1:<CUENTA>:bucket/lkh-lab-tables
aws s3tables create-namespace --table-bucket-arn $ARN --namespace silver
aws s3tables create-namespace --table-bucket-arn $ARN --namespace gold
```

✅ En `lkh-lab-tables` aparecen los namespaces `silver` y `gold`, todavía sin tablas.

> **¿No viste la opción de integración en el paso 3.1?** Revisa en **AWS Glue → Data Catalog → Catalogs** si existe `s3tablescatalog`. Si no existe, puedes crearlo con el mismo comando que usa el repo: está en `scripts/etapas.sh`, función `etapa_infra`.

---

## 4. Rol IAM para Glue

### 4.1 Crear el rol

1. Ve a **IAM** → **Roles** → **Create role**.
2. **Trusted entity type:** AWS service · **Use case:** **Glue** → **Next**.
3. En **Permissions policies**, busca y marca **AWSGlueServiceRole** → **Next**.
4. **Role name:** `lkh-lab-role-glue-us-east-1`.
5. **Tags:** los 4 tags → **Create role**.

### 4.2 Darle acceso solo a TU bucket y TU table bucket

1. Abre el rol → **Add permissions** → **Create inline policy** → pestaña **JSON**.
2. Pega esto, reemplazando las dos veces `<CUENTA>` en el bucket y las dos en el table bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LeerBronzeYScripts",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::lkh-lab-raw-<CUENTA>-us-east-1",
        "arn:aws:s3:::lkh-lab-raw-<CUENTA>-us-east-1/*"
      ]
    },
    {
      "Sid": "EscribirS3Tables",
      "Effect": "Allow",
      "Action": "s3tables:*",
      "Resource": [
        "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/lkh-lab-tables",
        "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/lkh-lab-tables/*"
      ]
    }
  ]
}
```

3. **Next** → **Policy name:** `lkh-lab-policy-lakehouse` → **Create policy**.

> 🔍 **Mínimo privilegio:** el job puede leer y escribir solo en estos dos lugares. Si alguien reutiliza el rol para otro bucket, falla. Es lo que pide cualquier área de seguridad en banca y seguros.

---

## 5. Jobs de Glue

Vas a crear 3 jobs con la misma configuración. Solo cambian el nombre, el script y los parámetros.

### 5.1 Crear el job `lkh-lab-job-bronze-to-silver`

1. Ve a **AWS Glue** → **ETL jobs** → **Script editor**.
2. **Engine:** Spark · **Options:** **Upload script** → elige `glue/bronze_to_silver.py` → **Create script**.
3. Arriba a la izquierda, cambia el nombre *Untitled job* por `lkh-lab-job-bronze-to-silver`.
4. Pestaña **Job details**:

| Campo | Valor |
|---|---|
| **IAM Role** | `lkh-lab-role-glue-us-east-1` |
| **Type** | Spark |
| **Glue version** | **Glue 5.0** |
| **Language** | Python 3 |
| **Worker type** | G.1X |
| **Requested number of workers** | `2` |
| **Job timeout (minutes)** | `20` |
| **Number of retries** | `0` |

5. Abre **Advanced properties**:
   - **Script filename:** `bronze_to_silver.py`
   - **Script path:** `s3://lkh-lab-raw-<CUENTA>-us-east-1/scripts/`
   - **Job parameters** → **Add new parameter**, uno por fila:

| Key | Value |
|---|---|
| `--datalake-formats` | `iceberg` |
| `--RAW_BUCKET` | `lkh-lab-raw-<CUENTA>-us-east-1` |
| `--TABLE_BUCKET_ARN` | `arn:aws:s3tables:us-east-1:<CUENTA>:bucket/lkh-lab-tables` |
| `--AWS_REGION_NAME` | `us-east-1` |

   - **Tags:** los 4 tags, más `Capa` = `silver`.
6. **Save** (arriba a la derecha).

> ⚠️ Las keys llevan **dos guiones** (`--RAW_BUCKET`) y van en mayúsculas, tal como las lee el script con `getResolvedOptions`. Un guion de menos y el job falla al arrancar.

### 5.2 Los otros dos jobs

Repite **5.1** con estos cambios. Ninguno de los dos lleva `--RAW_BUCKET`, porque leen de Silver y no de Bronze:

| Job | Script | Parámetros | Tag `Capa` |
|---|---|---|---|
| `lkh-lab-job-silver-to-gold` | `silver_to_gold.py` | `--datalake-formats`, `--TABLE_BUCKET_ARN`, `--AWS_REGION_NAME` | `gold` |
| `lkh-lab-job-silver-auditoria` | `silver_auditoria.py` | `--datalake-formats`, `--TABLE_BUCKET_ARN`, `--AWS_REGION_NAME` | `silver` |

✅ En **ETL jobs** ves los 3 jobs. Todavía no los ejecutes.

---

## 6. Workgroup de Athena

1. Ve a **Amazon Athena** → menú izquierdo **Workgroups** → **Create workgroup**.
2. **Workgroup name:** `lkh-lab-wg-analistas` · **Description:** *Workgroup de analistas con tope de 1 GB por consulta*.
3. **Analytics engine:** Athena SQL.
4. **Query result configuration:**
   - **Location of query result:** `s3://lkh-lab-raw-<CUENTA>-us-east-1/athena-results/`
   - Marca **Override client-side settings**: así nadie puede mandar sus resultados a otro lado.
5. **Settings** → **Per query data usage control** → **Data limits:** `1` **GB**.
6. **Tags:** los 4 tags → **Create workgroup**.

> 🔍 El tope de 1 GB cancela cualquier consulta que intente escanear más. Es tu seguro contra un `SELECT *` sobre una tabla gigante.

---

## 7. Lab 1 · Bronze: tablas en Athena

1. En Athena → **Query editor**, arriba a la derecha elige el workgroup **`lkh-lab-wg-analistas`**.
2. A la izquierda, en la sección **Data**: **Data source** = `AwsDataCatalog` y **Catalog** = `None`.
3. Abre `sql/bronze_ddl.sql` en un editor de texto y **reemplaza**:
   - `__DB_BRONZE__` → `lkh_lab_bronze`
   - `__RAW_BUCKET__` → `lkh-lab-raw-<CUENTA>-us-east-1`
4. Copia **una sentencia a la vez** (de `CREATE` hasta su `;`), pégala en el editor y dale **Run**. Son 5 en total: la base y 4 tablas.

> Athena ejecuta una sentencia por vez. Si pegas todo junto, corre solo la primera o da error.

5. Refresca el panel izquierdo (↻) y elige **Database** = `lkh_lab_bronze`: aparecen las 4 tablas. La base recién existe después de la primera sentencia (`CREATE DATABASE`); antes solo verás `default`. Si no la encuentras en el panel, no importa: las consultas usan el nombre completo (`lkh_lab_bronze.siniestros`).

✅ **Verifica** el desorden que vamos a limpiar:

```sql
SELECT estado, count(*) AS n
FROM lkh_lab_bronze.siniestros
GROUP BY estado ORDER BY n DESC;
```

Vas a ver `PAGADO`, `pagado`, `  Pagado `… Debajo del resultado, mira **Data scanned**: así se calcula lo que cobra Athena.

Sigue con las preguntas de [labs/lab1-bronze](../lab1-bronze/README.md).

---

## 8. Lab 2 · Silver

1. **AWS Glue** → **ETL jobs** → `lkh-lab-job-bronze-to-silver` → **Run**.
2. Pestaña **Runs**: el estado pasa de *Starting* a *Running* y luego a **Succeeded** en unos 3–5 minutos. Mientras tanto, lee el código en la pestaña **Script**.
3. Si falla, haz clic en la ejecución → **Error logs** (CloudWatch) y revisa *Problemas comunes* abajo.

✅ **Verifica en Athena:**
1. En el panel izquierdo: **Data source** = `AwsDataCatalog`, **Catalog** = `s3tablescatalog/lkh-lab-tables`, **Database** = `silver`. Si tu consola no muestra el campo **Catalog**, usa el nombre completo en la consulta: `FROM "s3tablescatalog/lkh-lab-tables"."silver"."siniestros"`.
2. Ejecuta:

```sql
SELECT estado, count(*) AS n FROM siniestros GROUP BY estado;
SELECT count(*) - count(DISTINCT id_siniestro) AS duplicados FROM siniestros;
-- Busca clasificacion = confidencial
SHOW TBLPROPERTIES clientes;
```

También puedes ver las tablas en **S3 → Table buckets → lkh-lab-tables → silver**.

Sigue con [labs/lab2-silver](../lab2-silver/README.md).

---

## 9. Lab 3 · Gold

1. **AWS Glue** → `lkh-lab-job-silver-to-gold` → **Run** → espera **Succeeded** (~3 min).
2. En Athena cambia **Database** a `gold` y ejecuta:

```sql
SELECT producto, anio, primas_cobradas, siniestros_pagados, ratio_siniestralidad
FROM agg_siniestralidad_producto_anual
ORDER BY anio DESC, ratio_siniestralidad DESC;
```

✅ Debe salir SALUD arriba, con la peor siniestralidad.

Sigue con [labs/lab3-gold](../lab3-gold/README.md).

---

## 10. Lab 4 · Auditoría y time travel

1. **Antes de correr el job**, mira cómo está el siniestro hoy (Database = `silver`):

```sql
SELECT id_siniestro, estado, monto_pagado FROM siniestros WHERE id_siniestro = 'SIN-00042';
```

2. **Anota la hora en UTC.** Puedes verla en la consulta misma: `SELECT current_timestamp;`
3. **AWS Glue** → `lkh-lab-job-silver-auditoria` → **Run** → espera **Succeeded**.
4. En la ejecución, abre **Output logs**: el job imprime el **ANTES** (por time travel), el **AHORA** y el historial de snapshots.
5. Repite en Athena, ahora con time travel. Usa la hora que anotaste en el paso 2:

```sql
-- Ahora
SELECT id_siniestro, estado, monto_pagado, flag_fraude
FROM siniestros WHERE id_siniestro = 'SIN-00042';

-- Antes de la corrección
SELECT id_siniestro, estado, monto_pagado
FROM siniestros FOR TIMESTAMP AS OF TIMESTAMP 'AAAA-MM-DD HH:MM:SS UTC'
WHERE id_siniestro = 'SIN-00042';

-- Historial de cambios
SELECT * FROM "siniestros$history";
```

✅ El **antes** dice `PAGADO · 17250.00`; el **ahora**, `RECHAZADO · 0.00 · true`.

Sigue con [labs/lab4-auditoria](../lab4-auditoria/README.md). El Lab 5 es una demo: [labs/lab5-gobierno](../lab5-gobierno/README.md).

---

## 11. Limpieza manual

**Hazlo en este orden:** un table bucket con tablas no se puede borrar, y un bucket con objetos tampoco.

| # | Dónde | Qué borrar |
|---|---|---|
| 1 | **S3 → Table buckets → lkh-lab-tables** | Las tablas de `silver` (4) y `gold` (3), luego los namespaces `silver` y `gold`, y al final el table bucket. Si la consola no te deja borrar alguno, usa el bloque de CloudShell de abajo |
| 2 | **Athena → Query editor** (Data source `AwsDataCatalog`, Catalog `None`) | `DROP DATABASE lkh_lab_bronze CASCADE;`. Solo borra la definición de las tablas; los CSV se van en el paso 5 |
| 3 | **Athena → Workgroups** | `lkh-lab-wg-analistas` → **Delete**. Confirma que se borren también las consultas guardadas |
| 4 | **AWS Glue → ETL jobs** | Los 3 jobs `lkh-lab-job-*` → **Actions → Delete job(s)** |
| 5 | **S3 → General purpose buckets** | `lkh-lab-raw-…` → **Empty** (escribe *permanently delete*) → luego **Delete** |
| 6 | **IAM → Roles** | `lkh-lab-role-glue-us-east-1` → **Delete** |
| 7 | **Billing → Budgets** | `lkh-lab-budget-5usd` → **Delete** |
| 8 | **CloudWatch → Log groups** *(opcional)* | `/aws-glue/jobs/output` y `/aws-glue/jobs/error`: borra los streams del lab o pon retención de 7 días |

**Borrar las tablas desde CloudShell** (paso 1), reemplazando `<CUENTA>`:

```bash
ARN=arn:aws:s3tables:us-east-1:<CUENTA>:bucket/lkh-lab-tables
for t in clientes polizas pagos_primas siniestros; do
  aws s3tables delete-table --table-bucket-arn $ARN --namespace silver --name $t; done
for t in agg_siniestralidad_producto_anual agg_siniestros_producto_mensual agg_cartera_region_producto; do
  aws s3tables delete-table --table-bucket-arn $ARN --namespace gold --name $t; done
aws s3tables delete-namespace --table-bucket-arn $ARN --namespace silver
aws s3tables delete-namespace --table-bucket-arn $ARN --namespace gold
aws s3tables delete-table-bucket --table-bucket-arn $ARN
```

> Lo único que conviene **dejar** es el catálogo `s3tablescatalog` de Glue: es compartido por toda la cuenta, no cobra, y otros table buckets lo usan.

> 💡 **Atajo:** como usaste los mismos nombres que el estándar, también puedes clonar el repo en CloudShell y correr `./cleanup.sh`. Como no hay stack de CloudFormation, entra en *modo huérfanos* y limpia lo que encuentre con esos nombres.

---

## Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| El job falla con `Stage-create is currently not supported` | Estás usando un script viejo, que crea tablas con CTAS (`createOrReplace`). Vuelve a subir a `scripts/` los `.py` de este repo, que usan `CREATE TABLE` + `append()` |
| El job falla con `AccessDenied` sobre `s3tables` | El ARN de la política inline (paso 4.2) o el parámetro `--TABLE_BUCKET_ARN` no coinciden con tu table bucket. Compáralos letra por letra |
| `KeyError` o *missing argument* al arrancar el job | Falta un parámetro, o le falta un guion (`-RAW_BUCKET`). Revisa el paso 5.1 |
| Athena no muestra `s3tablescatalog` | No se activó la integración. Revisa la nota al final del paso 3 |
| Athena no ve `silver` o `gold`, o da error de Lake Formation | Tu cuenta tiene la integración con Lake Formation. Date permisos sobre `s3tablescatalog/lkh-lab-tables` en Lake Formation (ver *Problemas comunes* del README principal) |
| `This query ran against the "default" database` o resultados vacíos | No elegiste el workgroup, el catálogo o la base correcta en el panel izquierdo |
| La tabla de Bronze sale vacía | El CSV no está en su carpeta (`bronze/<tabla>/`) o el `LOCATION` del DDL no tiene tu bucket |

---

## Lo que acabas de hacer a mano vs. el script

| A mano (este manual) | Automatizado |
|---|---|
| ~60–90 min de clics | `./deploy.sh` en ~10–12 min |
| Fácil equivocarse en un ARN o un parámetro | Los nombres salen de un solo lugar (`configurar_nombres`) |
| Para un entorno `dev` hay que repetirlo todo | `./deploy.sh --entorno dev` |
| Borrar requiere seguir un orden | `./cleanup.sh` |

**Moraleja para tu CV:** saber hacerlo en la consola te ayuda a entender cada pieza; tenerlo como código es lo que te pide una empresa.
