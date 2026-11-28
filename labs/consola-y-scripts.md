# Consola y scripts: cómo combinarlos

**La idea:** puedes construir el Lakehouse **paso a paso en la consola de AWS** ([manual por consola](manual-consola/README.md)) o con los scripts, y mezclar ambos caminos. Si te quedas a mitad de algo en la consola, un script te pone al día sobre lo mismo que ya hiciste a mano.

Esto funciona porque los scripts **detectan cómo se creó tu infraestructura** y trabajan sobre ella:

| Si tu infraestructura… | Los scripts… |
|---|---|
| la creó `./lab.sh 0` o `./deploy.sh` (CloudFormation) | usan el stack `lkh-lab-stack` |
| la creaste **a mano en la consola** | usan tus recursos por sus nombres (`lkh-lab-*`), sin lanzar CloudFormation encima |
| no existe todavía | te piden empezar por el Lab 0 |

---

## 1. ¿Dónde estoy?

Antes de nada, este comando te dice qué labs tienes hechos y qué comando sigue:

```bash
./lab.sh estado
```

```
==> Estado de tu Lakehouse (lkh-lab en us-east-1)
   Origen: creado a mano en la consola (sin stack)

   Lab 0 · Infraestructura  ✔ hecho
   Lab 1 · Bronze           ✔ hecho
   Lab 2 · Silver           · pendiente
   Lab 3 · Gold             · pendiente
   Lab 4 · Auditoria        · pendiente

   Siguiente paso: ./lab.sh 2
```

> Todo se corre en **AWS CloudShell** (ícono `>_` en la consola): `git clone <url-del-repo> && cd lab_lakehouse0`.

---

## 2. Ponerte al día con un comando

Busca en qué parte del manual te quedaste:

| Me quedé en… (manual) | Ejecuta | Tiempo |
|---|---|---|
| Partes 1 a 6: infraestructura, **sin haber creado nada** | `./lab.sh 0` | ~3 min |
| Partes 1 a 6: infraestructura, **a medio crear** | `./lab.sh 0 --reiniciar` | ~4 min |
| Parte 7 · Lab 1 Bronze | `./lab.sh 1` | ~1 min |
| Parte 8 · Lab 2 Silver | `./lab.sh 2` | ~4 min |
| Parte 9 · Lab 3 Gold | `./lab.sh 3` | ~3 min |
| Parte 10 · Lab 4 Auditoría | `./lab.sh 4` | ~3 min |
| Varias partes atrás | `./deploy.sh --hasta silver` / `gold` | ~5–8 min |

**Después, puedes volver a la consola.** Todo lo que el script creó tiene los mismos nombres que el manual, así que los siguientes pasos en la consola funcionan igual.

### `--reiniciar`: cuándo usarlo
Si te quedaste **mientras creabas la infraestructura a mano** (por ejemplo, creaste el bucket pero no el rol ni los jobs), `./lab.sh 0` no lanza CloudFormation encima, porque chocaría con tus recursos. Te avisa y te ofrece:

```bash
./lab.sh 0 --reiniciar
```

Borra lo que creaste a mano con los nombres del estándar (`./cleanup.sh`) y despliega todo por script. En ~4 minutos estás al día.

---

## 3. Lo que los scripts revisan en tu infraestructura de la consola

Cuando la infraestructura es tuya (hecha a mano), cada `./lab.sh N` revisa **antes de correr** que tenga lo que ese lab necesita. Los errores típicos de hacerlo a mano aparecen aquí y no cinco minutos después en un job fallido:

| Revisa | Si está mal |
|---|---|
| Bucket `lkh-lab-raw-<cuenta>-<región>` y workgroup con ubicación de resultados | Te dice qué falta y en qué paso del manual se crea |
| Namespaces `silver` y `gold` | **Los crea solo** si te los saltaste |
| Integración `s3tablescatalog` para Athena | **La crea sola** si no está |
| Scripts en `s3://…/scripts/` | **Los sube solo** (siempre la última versión) |
| Rol IAM `lkh-lab-role-glue-<región>` | Te dice que falta (paso 4) |
| Cada job de Glue: existe, script correcto, Glue 5.0, `--datalake-formats`, `--TABLE_BUCKET_ARN`, `--RAW_BUCKET`, `--AWS_REGION_NAME` | Te dice exactamente qué parámetro está mal y qué valor debe tener (paso 5.1) |

Ejemplo, con un ARN mal copiado en el job:

```
Tu infraestructura de la consola no esta completa para el Lab 2:
   - lkh-lab-job-bronze-to-silver: --TABLE_BUCKET_ARN debe ser arn:aws:s3tables:us-east-1:123456789012:bucket/lkh-lab-tables (tiene: arn:aws:s3tables:us-east-1:123456789012:bucket/lkh-lab-table)  (manual: paso 5.1)

  Corrigelo en la consola siguiendo labs/manual-consola, o pasate a la ruta por script:
     ./lab.sh 0 --reiniciar   (borra lo creado a mano y despliega todo por script, ~4 min)
```

---


## 4. Cómo se verifica que todo esto funciona

El repo trae una verificación automática que **no necesita cuenta de AWS**. Corre en GitHub Actions en cada push y también en tu máquina:

```bash
pip install cfn-lint shellcheck-py pyyaml pyspark==3.5.4   # una vez (y Java 17 para la capa 5)
tests/verificar.sh              # todo, con la lógica de Spark simulada
tests/verificar.sh --iceberg    # igual, con Iceberg real (incluye el Lab 4)
tests/verificar.sh --rapido     # sin Spark: segundos
```

| Capa | Qué garantiza | Archivo |
|---|---|---|
| 1 · Sintaxis | Los `.sh` pasan `bash -n` y `shellcheck`; los `.py` compilan | `tests/verificar.sh` |
| 2 · Plantilla | `infra/template.yaml` pasa `cfn-lint` | `tests/verificar.sh` |
| 3 · Consistencia | El **manual por consola** y los **scripts** crean lo mismo: nombres, parámetros de cada job, política IAM, reglas del bucket, tope de Athena, tags, tablas. También: los CSV del repo son idénticos a los que genera el script, ningún job usa CTAS (S3 Tables no lo soporta), los scripts son ejecutables y los enlaces de los `.md` existen | `tests/test_consistencia.py` |
| 4 · Flujos | Con una AWS simulada con estado: la ruta script, la ruta consola, cada error típico de la consola, los rescates (`--hasta`, `--reiniciar`), los prerequisitos entre labs y la limpieza en ambos modos | `tests/test_flujos.sh`, `tests/aws_simulado/aws` |
| 5 · Lógica | Los jobs de Glue **reales** corren en PySpark sobre los CSV: limpieza de Silver, KPIs de Gold (incluido el 87.8 % de SALUD del Lab 3) y, con `--iceberg`, el Lab 4 completo: `ALTER`, `UPDATE`, snapshots, time travel e idempotencia | `tests/test_logica.py` |

**Lo que esta verificación no cubre:** permisos reales de IAM o Lake Formation de tu cuenta, cuotas, y la conexión de Glue con el endpoint Iceberg REST de S3 Tables. Eso solo se comprueba corriendo los labs en una cuenta real.
