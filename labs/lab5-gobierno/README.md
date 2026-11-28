# Lab 5 · Gobierno (opcional)

## 🎯 Objetivo
Entender cómo se protegen los datos personales del asegurado: **cada rol ve solo lo que necesita**. La misma tabla, el mismo motor (Athena), pero cada rol ve columnas distintas, definidas en un solo lugar.

## ⚠️ Antes de empezar: por qué este lab es manual
El despliegue usa la integración de S3 Tables con **control de acceso por IAM**, que es la opción por defecto y la más simple. IAM da acceso a una tabla completa o a nada. Para dar permisos **por columna** hay que pasar el catálogo `s3tablescatalog` a **AWS Lake Formation**.

Ese cambio:
- **Afecta a toda la cuenta**, no solo al lab.
- **Corta el acceso por IAM apenas lo activas**: nadie consulta las tablas de Silver y Gold hasta que des permisos de Lake Formation, ni siquiera tú.

Por eso no se automatiza. Hazlo solo en **una cuenta tuya de pruebas**, **después de terminar los Labs 1 a 4**, y al final [vuelve a IAM](#-paso-6--volver-a-como-estaba).

> **No uses el usuario root.** El administrador del data lake tiene que ser un usuario o rol de IAM. Revisa con qué identidad trabajas con `aws sts get-caller-identity --query Arn --output text`: si termina en `:root`, crea un usuario IAM con la política `AdministratorAccess` y haz todo el lab con él.

## 🧩 Lo que ya tienes aplicado (sin Lake Formation)
- **Separación por capas:** Silver tiene PII (`clientes.dni`, `nombre`, `email`); Gold no.
- **Gold sin PII:** `gold.agg_cartera_region_producto` agrega por departamento y producto, sin un solo dato personal.
- **Clasificación como metadato:** cada tabla lleva la propiedad `clasificacion` (`confidencial` o `interna`).
- **Mínimo privilegio:** el rol de Glue solo accede a su bucket y a su table bucket (revisa `GlueRole` en `infra/template.yaml`).

Compruébalo en Athena (catálogo `s3tablescatalog/lkh-lab-tables`):

```sql
-- Silver: hay PII
SELECT * FROM silver.clientes LIMIT 5;
```

```sql
-- Gold: no hay forma de identificar a una persona
SELECT * FROM gold.agg_cartera_region_producto LIMIT 5;
```

```sql
-- La clasificación viaja con la tabla
SHOW TBLPROPERTIES silver.clientes;
```

---

## ▶️ Paso 1 · Hazte administrador del data lake
Consola de **Lake Formation** → *Administration* → *Administrative roles and tasks* → *Data lake administrators* → **Add**, y agrega tu usuario o rol de IAM. La primera vez que abres Lake Formation, la consola también te ofrece agregarte.

## ▶️ Paso 2 · Crea los roles de prueba
En **IAM**, crea el rol `lkh-lab-role-analista-riesgos` (y, si quieres un tercer caso, `lkh-lab-role-comercial`):

- **Trust policy:** tu misma cuenta, para poder cambiar a ese rol desde la consola (*Switch role*).
- **Permisos IAM:**
  - Athena sobre el workgroup `lkh-lab-wg-analistas`.
  - Lectura y escritura en `s3://lkh-lab-raw-<CUENTA>-us-east-1/athena-results/`.
  - `glue:GetCatalog*`, `glue:GetDatabase*`, `glue:GetTable*`.
  - `lakeformation:GetDataAccess`: Lake Formation lo usa para entregar credenciales temporales de acceso a los datos.
- **No** le des permisos `s3tables:*`: el acceso a los datos lo controla Lake Formation.

Lake Formation también necesita un rol propio para leer los table buckets, por ejemplo `lkh-lab-role-lakeformation`. Su política está en la guía oficial (ver [Referencias](#-referencias)).

## ▶️ Paso 3 · Pasa el catálogo a Lake Formation
En CloudShell, reemplazando `<CUENTA>`:

```bash
aws lakeformation register-resource \
  --resource-arn "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/*" \
  --role-arn "arn:aws:iam::<CUENTA>:role/lkh-lab-role-lakeformation" \
  --with-federation
```

```bash
aws glue update-catalog \
  --catalog-id "s3tablescatalog" \
  --catalog-input '{
    "FederatedCatalog": {
      "Identifier": "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/*",
      "ConnectionName": "aws:s3tables"
    },
    "CreateDatabaseDefaultPermissions": [],
    "CreateTableDefaultPermissions": [],
    "AllowFullTableExternalDataAccess": "True"
  }'
```

Las listas vacías son el cambio de fondo: desde ahora las bases y tablas del catálogo se gestionan con permisos de Lake Formation y no con los permisos IAM por defecto.

## ▶️ Paso 4 · Da los permisos
*Lake Formation* → *Data permissions* → **Grant**. El catálogo es `s3tablescatalog/lkh-lab-tables`.

| A quién | Recurso | Permiso |
|---|---|---|
| Tu usuario | Bases `silver` y `gold` (todas las tablas) | `SELECT`, `DESCRIBE` |
| Rol de Glue del lab, si vas a volver a correr jobs | Bases `silver` y `gold` | `ALL` |
| `lkh-lab-role-analista-riesgos` | Tabla `silver.clientes`, **solo** columnas `id_cliente` y `departamento` (*Column-based access* → *Include columns*) | `SELECT` |
| `lkh-lab-role-analista-riesgos` | Base `gold` (todas las tablas) | `SELECT`, `DESCRIBE` |
| `lkh-lab-role-comercial` | Solo `gold.agg_cartera_region_producto` | `SELECT`, `DESCRIBE` |

Primero date permisos a ti: si no, te quedas sin poder consultar.

> Los jobs de Glue del lab escriben por el endpoint Iceberg REST de S3 Tables con permisos `s3tables:*` de su rol. Si al volver a correrlos fallan con Lake Formation activo, dale al rol `lkh-lab-role-glue-<región>` el permiso `ALL` de la tabla anterior y agrégale `lakeformation:GetDataAccess` en IAM.

## ✅ Paso 5 · Comprueba que cada rol ve algo distinto

1. Como tú, en Athena: `SELECT * FROM silver.clientes LIMIT 5;` muestra todas las columnas.
2. Cambia al rol `lkh-lab-role-analista-riesgos` (menú de tu usuario → *Switch role*) y en el workgroup `lkh-lab-wg-analistas`:

```sql
-- Mismo SELECT *: solo salen id_cliente y departamento
SELECT * FROM silver.clientes LIMIT 5;
```

```sql
-- Una columna no permitida: error de permisos
SELECT dni FROM silver.clientes LIMIT 5;
```

```sql
-- Gold funciona normal
SELECT * FROM gold.agg_cartera_region_producto LIMIT 10;
```

## ↩️ Paso 6 · Volver a como estaba
Hazlo antes de `./cleanup.sh`. El lab creó el catálogo con permisos `ALL` para `IAM_ALLOWED_PRINCIPALS`, así que volver es poner exactamente eso.

1. **Acceso IAM primero.** El rol de Glue ya tiene `s3tables:*` y tu usuario es administrador, así que este paso ya está cubierto. El acceso por Lake Formation termina apenas corres el paso 2.
2. **Devuelve el catálogo a IAM:**

```bash
aws glue update-catalog \
  --catalog-id "s3tablescatalog" \
  --catalog-input '{
    "FederatedCatalog": {
      "Identifier": "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/*",
      "ConnectionName": "aws:s3tables"
    },
    "CreateDatabaseDefaultPermissions": [
      {"Principal": {"DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"}, "Permissions": ["ALL"]}
    ],
    "CreateTableDefaultPermissions": [
      {"Principal": {"DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"}, "Permissions": ["ALL"]}
    ],
    "OverwriteChildResourcePermissionsWithDefault": "Accept",
    "AllowFullTableExternalDataAccess": "True"
  }'
```

`OverwriteChildResourcePermissionsWithDefault: Accept` aplica el cambio también a las bases y tablas que ya existen.

3. **Quita el registro en Lake Formation:**

```bash
aws lakeformation deregister-resource \
  --resource-arn "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/*"
```

4. **Comprueba y limpia:** `./lab.sh estado` y una consulta a `silver` en Athena deben funcionar como antes. Borra los roles `lkh-lab-role-analista-riesgos`, `lkh-lab-role-comercial` y `lkh-lab-role-lakeformation`, y recién entonces corre `./cleanup.sh`.

Lo único que no vuelve es el permiso por columna, y es lo esperado: los controles finos (por columna y filtros de celdas) solo existen con Lake Formation.

## 🛠️ Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| Después del paso 3 no puedes consultar nada | Te faltan tus propios permisos de Lake Formation (paso 4, primera fila) |
| El rol del analista da *Access denied* hasta en Gold | Le falta `lakeformation:GetDataAccess` en IAM o el permiso sobre la base `gold` |
| No puedes agregarte como administrador del data lake | Estás como root, o a tu usuario le falta `AdministratorAccess` |
| `./lab.sh 4` falla con Lake Formation activo | Dale al rol de Glue el permiso `ALL` sobre `silver` (paso 4) |

## 💬 Para pensar
- En la Ley de Protección de Datos Personales de tu país, ¿qué datos de esta tabla se consideran sensibles?
- ¿Quién debería aprobar un permiso sobre `silver.clientes` en tu empresa?

## 📚 Referencias
- [Lake Formation · Cambiar el control de acceso de IAM a Lake Formation (S3 Tables)](https://docs.aws.amazon.com/lake-formation/latest/dg/change-access-iam-to-lf.html)
- [Lake Formation · Cambiar el control de acceso de Lake Formation a IAM](https://docs.aws.amazon.com/lake-formation/latest/dg/change-access-lf-to-iam.html)
- *Amazon S3 Tables integration with AWS Glue Data Catalog and AWS Lake Formation*, en la AWS Lake Formation Developer Guide.

➡️ Para terminar: `./cleanup.sh` y [llévalo a tu CV](../../README.md#-llévalo-a-tu-cv)
