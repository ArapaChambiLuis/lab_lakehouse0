# Guía de la demo por lab: cómo demostrar cada lab en la consola de AWS

Guion para el **presentador**. La demo construye el Lakehouse **en vivo, en la consola**, incluida la infraestructura. Los asistentes siguen en sus cuentas, y quien se pierde alcanza al grupo con `./lab.sh`.

- **Cómo crear cada cosa, clic por clic:** [manual por consola](manual-consola/README.md). Este guion no lo repite: dice **qué mostrar, qué decir y cómo cuidar el tiempo**.
- **Cómo rescatar a quien se pierde:** [demo en consola + rescate](demo-consola-y-rescate.md).

---

## Agenda con la infraestructura en vivo (120 min)

Crear la infraestructura en vivo toma unos 30 minutos, así que la agenda queda así:

| Hora | Bloque | Min | En pantalla |
|---|---|---|---|
| 0:00 | Apertura | 8 | Slides |
| 0:08 | Conceptos | 12 | Slides |
| 0:20 | **[Lab 0 · Infraestructura en vivo](#lab-0--infraestructura-en-vivo--32-min)** | 32 | Consola: Budgets, S3, S3 Tables, IAM, Glue, Athena |
| 0:52 | [Lab 1 · Bronze](#lab-1--bronze--8-min) | 8 | S3 y Athena |
| 1:00 | [Lab 2 · Silver](#lab-2--silver--15-min) | 15 | Glue, S3 Tables y Athena |
| 1:15 | [Lab 3 · Gold](#lab-3--gold--12-min) | 12 | Glue y Athena |
| 1:27 | [Lab 4 · Auditoría](#lab-4--auditoría-y-time-travel--15-min) ⭐ | 15 | Athena, Glue y CloudWatch |
| 1:42 | [Lab 5 · Gobierno](#lab-5--gobierno-demo--6-min) | 6 | Lake Formation y Athena |
| 1:48 | [Cierre y limpieza](#cierre--limpieza-y-preguntas--12-min) | 12 | CloudShell y slides |

> ⚠️ El slide de agenda del deck tiene los tiempos de la versión anterior, con el Lab 0 por script. Actualízalo con esta tabla.

---

## Antes del evento

### Una semana antes
- [ ] Ensayo completo con cronómetro, siguiendo esta guía.
- [ ] Desplegar un **Lakehouse de respaldo** con otro entorno, para mostrar resultados si algo falla en vivo:
  ```bash
  ./deploy.sh --entorno bkp      # crea lkh-bkp-*, completo hasta el Lab 4
  ```
  Si un job falla en vivo, en Athena eliges el catálogo `s3tablescatalog/lkh-bkp-tables` y sigues. Bórralo después del evento con `./cleanup.sh --entorno bkp`.

### El día de la demo, 30 minutos antes
1. **Cuenta limpia:** en CloudShell, `./lab.sh estado` debe decir *"Origen: todavia no hay nada creado"*.
2. **Región `us-east-1`** seleccionada en la consola.
3. **Zoom del navegador al 125–150 %**: la consola de AWS tiene letra chica para un proyector.
4. **Pestañas abiertas, en este orden:** Billing → Budgets · S3 · IAM → Roles · AWS Glue → ETL jobs · Athena · CloudShell.
5. **Kit de valores** generado en CloudShell (bloque de abajo). Deja `valores.txt` visible en una ventana aparte: de ahí copias cada nombre y cada ARN.
6. En tu laptop: descarga `subir.zip` (CloudShell → **Actions → Download file** → `kit-demo/subir.zip`) y descomprímelo. Así subes las carpetas a S3 arrastrándolas.

### Kit de valores (CloudShell)

Pega esto en CloudShell desde la carpeta del repo. Los asistentes también deberían correrlo al empezar el Lab 0:

```bash
cd ~/lab_lakehouse0
CUENTA=$(aws sts get-caller-identity --query Account --output text)
mkdir -p ~/kit-demo
cat > ~/kit-demo/valores.txt <<EOF
Cuenta ............ $CUENTA
Region ............ us-east-1
Bucket S3 ......... lkh-lab-raw-$CUENTA-us-east-1
Table bucket ...... lkh-lab-tables
Table bucket ARN .. arn:aws:s3tables:us-east-1:$CUENTA:bucket/lkh-lab-tables
Rol IAM ........... lkh-lab-role-glue-us-east-1
Ruta de scripts ... s3://lkh-lab-raw-$CUENTA-us-east-1/scripts/
Workgroup ......... lkh-lab-wg-analistas
Resultados Athena . s3://lkh-lab-raw-$CUENTA-us-east-1/athena-results/
Jobs .............. lkh-lab-job-bronze-to-silver
                    lkh-lab-job-silver-to-gold
                    lkh-lab-job-silver-auditoria
EOF
python3 - "$CUENTA" <<'PY'
import pathlib, re, sys
manual = pathlib.Path("labs/manual-consola/README.md").read_text(encoding="utf-8")
politica = re.search(r"`{3}json\n(.*?)`{3}", manual, re.S).group(1).replace("<CUENTA>", sys.argv[1])
(pathlib.Path.home() / "kit-demo" / "politica-glue.json").write_text(politica)
PY
sed -e "s/__DB_BRONZE__/lkh_lab_bronze/g" -e "s/__RAW_BUCKET__/lkh-lab-raw-$CUENTA-us-east-1/g" \
  sql/bronze_ddl.sql > ~/kit-demo/bronze_ddl_listo.sql
rm -rf ~/kit-demo/subir && mkdir -p ~/kit-demo/subir/scripts
for t in clientes polizas pagos_primas siniestros; do
  mkdir -p ~/kit-demo/subir/bronze/$t && cp data/sample/$t.csv ~/kit-demo/subir/bronze/$t/
done
cp glue/*.py ~/kit-demo/subir/scripts/
(cd ~/kit-demo && python3 -m zipfile -c subir.zip subir/)
cat ~/kit-demo/valores.txt
```

Genera en `~/kit-demo/`:

| Archivo | Para qué |
|---|---|
| `valores.txt` | Todos los nombres y ARNs con **tu** cuenta, listos para copiar |
| `politica-glue.json` | La política inline del rol (paso 4.2) con tu cuenta ya puesta. Se genera desde el manual, así que siempre coincide |
| `bronze_ddl_listo.sql` | El DDL de Bronze sin placeholders, listo para Athena |
| `subir.zip` | Las carpetas `bronze/` (con una subcarpeta por tabla) y `scripts/`, para arrastrar a S3 |

Para ver un archivo: `cat ~/kit-demo/politica-glue.json`.

---

## Cómo leer cada ficha

| Sección | Qué contiene |
|---|---|
| 🎯 **Qué demuestras** | La idea que el público debe llevarse |
| 🖥️ **Pantallas** | El recorrido en la consola, en orden. **Muestra** = qué haces; **Di** = qué explicas |
| ⭐ **Momento clave** | El instante que hay que cuidar: no lo apures |
| ⏳ **Mientras esperas** | Qué decir mientras corre un job |
| ✅ **Verificación para todos** | Lo que cada asistente corre para confirmar que le funcionó |
| 🛟 **Si alguien se perdió** | El comando de rescate |
| 🔥 **Si falla en vivo** | El error más probable y tu plan B |

---

## Lab 0 · Infraestructura en vivo · 32 min

🎯 **Qué demuestras:** que un Lakehouse son seis piezas con responsabilidades claras, y que cada una se configura pensando en **costo, seguridad y nombres estándar**.

| Min | Parte (manual) | Muestra | Di |
|---|---|---|---|
| 0–2 | Preparación | CloudShell: `aws sts get-caller-identity` y el kit de valores | "Primero confirmen que están en **su** cuenta, no en la de su empresa. Este `valores.txt` es su chuleta: de ahí copian todo" |
| 2–4 | [1 · Budgets](manual-consola/README.md#1-alerta-de-costos-aws-budgets) | Crear `lkh-lab-budget-5usd` con alerta al 50 % | "Lo primero en cualquier cuenta, antes de crear nada: una alarma de costos" |
| 4–10 | [2 · Bucket S3](manual-consola/README.md#2-bucket-s3-para-bronze-scripts-y-athena) | Crear el bucket con sus tags → crear **una** regla de ciclo de vida en vivo (`limpiar-resultados-athena`) → arrastrar la carpeta `scripts/` | "El nombre lleva cuenta y región porque los buckets son únicos en el mundo. **Clasificacion = confidencial** porque aquí llega PII cruda" |
| 10–14 | [3 · Table bucket](manual-consola/README.md#3-table-bucket-de-s3-tables-silver-y-gold) | Crear `lkh-lab-tables` con **Enable integration** → namespaces `silver` y `gold` | "Esto es S3 Tables: un bucket hecho para tablas Iceberg. La integración es lo que le permite a Athena verlas" |
| 14–19 | [4 · Rol IAM](manual-consola/README.md#4-rol-iam-para-glue) | Crear el rol con `AWSGlueServiceRole` → política inline: pegar `politica-glue.json` | "Mínimo privilegio: este rol solo puede tocar **mi** bucket y **mi** table bucket. Es lo primero que revisa seguridad en banca" |
| 19–28 | [5 · Jobs de Glue](manual-consola/README.md#5-jobs-de-glue) | Crear `lkh-lab-job-bronze-to-silver` completo, **mostrando cada parámetro** → crear los otros dos con **Actions → Clone job** | "Los parámetros son el contrato entre el job y la infraestructura. Un ARN mal copiado aquí es el error número uno" |
| 28–30 | [6 · Workgroup](manual-consola/README.md#6-workgroup-de-athena) | Crear `lkh-lab-wg-analistas` con tope de 1 GB | "Este tope es el seguro contra un `SELECT *` sobre una tabla gigante" |
| 30–32 | Checkpoint | CloudShell: `./lab.sh estado` | ⭐ ver abajo |

⭐ **Momento clave, el checkpoint:** corre `./lab.sh estado` en tu CloudShell. Debe decir *"Origen: creado a mano en la consola"* y *"Lab 0 · Infraestructura ✔ hecho"*. Di: **"El script acaba de auditar todo lo que hicimos a mano: cada job, cada parámetro, cada ARN. Si alguien se equivocó en algo, el script le dice exactamente qué y en qué paso del manual."** Pide que todos lo corran.

**Trucos para no perder tiempo:**
- **Clonar jobs:** en *ETL jobs*, selecciona el primero → **Actions → Clone job** → cambia el nombre, el *Script filename* y los parámetros (al de Gold y al de auditoría se les quita `--RAW_BUCKET`). Si tu consola no tiene *Clone job*, créalos como el primero.
- **Regla multiparte:** créala antes del evento, o muéstrala ya creada, y explica para qué sirve.
- **Tags:** pon los tags completos en el **bucket** para mostrarlos. En el resto, dilo y agrégalos rápido.
- **La integración ya activada:** si en tu cuenta ya existe `s3tablescatalog`, la casilla aparece como activada. Aprovecha para decir: "esto se activa una vez por cuenta y región".

✅ **Verificación para todos:** `./lab.sh estado` → Lab 0 ✔ hecho.

🛟 **Si alguien se perdió:**
- No alcanzó a crear nada: `./lab.sh 0` (~3 min).
- Quedó a medias: `./lab.sh 0 --reiniciar` (~4 min).

🔥 **Si falla en vivo:**

| Síntoma | Qué hacer |
|---|---|
| `./lab.sh estado` marca algo pendiente en **tu** cuenta | Lee el mensaje en voz alta: es una demo perfecta de por qué existe el chequeo. Corrígelo en la consola y vuelve a correrlo |
| No aparece **Create namespace** en S3 Tables | Usa el bloque de CloudShell del paso 3.2 del manual |
| Te atrasaste más de 5 minutos | Crea solo el primer job en vivo y los otros dos con `./lab.sh 0 --reiniciar` en una cuenta de respaldo. O muestra los jobs ya creados en el entorno `lkh-bkp-*` |

---

## Lab 1 · Bronze · 8 min

🎯 **Qué demuestras:** que en Bronze el dato se guarda **tal como llegó**, con todos sus errores, y que eso es a propósito.

🖥️ **Pantallas:**
1. **S3 → tu bucket → Upload → Add folder** → arrastra `bronze/` desde `subir.zip`.
   **Di:** "Una carpeta por tabla: Athena lee una tabla como *todos los archivos de una carpeta*."
2. **Athena → Query editor:** elige el workgroup `lkh-lab-wg-analistas` **arriba a la derecha**, deja **Catalog** en `None` y **Database** en `default`, y pega y ejecuta cada sentencia de `bronze_ddl_listo.sql` (son 5). Después refresca el panel izquierdo (↻): aparece `lkh_lab_bronze`.
   **Muestra** dónde está cada control: el workgroup arriba a la derecha y la base en el panel izquierdo. Es donde más se pierde la gente.
   **Di:** "Todas las columnas son `string`. En Bronze no se confía en los tipos."
3. **Athena →** la consulta de estados (abajo).
   **Muestra** el **Data scanned** debajo del resultado.
   **Di:** "Así se cobra Athena: por datos escaneados. Esto costó fracciones de centavo."

⭐ **Momento clave:** el resultado con `PAGADO`, `pagado` y `  Pagado `. Pregunta al público: **"Si la gerencia ve un reporte hecho desde aquí, ¿cuántos siniestros pagados le decimos?"**

```sql
SELECT estado, count(*) AS n
FROM lkh_lab_bronze.siniestros
GROUP BY estado ORDER BY n DESC;
```

✅ **Verificación para todos:** la misma consulta muestra varias versiones de cada estado.

🛟 **Si alguien se perdió:** `./lab.sh 1` (~1 min).

🔥 **Si falla en vivo:**

| Síntoma | Qué hacer |
|---|---|
| La tabla sale vacía | El CSV quedó fuera de su carpeta: revisa que exista `bronze/siniestros/siniestros.csv` |
| Athena se queja de la ubicación de resultados | El workgroup no está elegido arriba a la derecha |
| `lkh_lab_bronze` no aparece en **Database** | **Catalog** debe estar en `None`: con `s3tablescatalog/...` solo se ven `silver` y `gold`. Refresca con ↻ |

---

## Lab 2 · Silver · 15 min

🎯 **Qué demuestras:** que Glue convierte datos sucios en **tablas Iceberg confiables**, y que las reglas de calidad son decisiones de negocio.

🖥️ **Pantallas:**
1. **Glue → `lkh-lab-job-bronze-to-silver` → Run.** Lánzalo **primero**: tarda 3–5 minutos.
2. Mientras corre, pestaña **Script**: recorre el código (ver *Mientras esperas*).
3. Pestaña **Runs**: *Running* → **Succeeded**.
4. **S3 → Table buckets → `lkh-lab-tables` → `silver`**: aparecen las 4 tablas.
   **Di:** "No hay archivos sueltos: son tablas, con historia y transacciones."
5. **Athena →** panel izquierdo: **Catalog** = `s3tablescatalog/lkh-lab-tables`, **Database** = `silver` → las consultas de abajo. Si a alguien no le aparece **Catalog**: `FROM "s3tablescatalog/lkh-lab-tables"."silver"."siniestros"`.

⏳ **Mientras esperas** (en la pestaña *Script*):
- **`SparkSession ... type = rest`:** "Glue habla con S3 Tables por el endpoint Iceberg REST, sin instalar nada."
- **`row_number()` sobre `id_siniestro`:** "Si un siniestro llegó dos veces, nos quedamos con el reporte más reciente."
- **`dato_incompleto`:** "No borramos la fila: la **marcamos**. Si borrarla o no lo decide el negocio, no el ingeniero."
- **`CREATE TABLE` + `append()`:** "S3 Tables todavía no soporta `CREATE TABLE AS SELECT`. Por eso primero se crea la tabla y luego se escribe."
- **`clasificacion = confidencial`** en clientes: "La clasificación viaja con la tabla."

⭐ **Momento clave:** la misma consulta de estados del Lab 1, ahora con **solo 3 estados limpios**. Ponlas lado a lado en dos pestañas del editor (**+**): una con **Catalog** = `None` y **Database** = `lkh_lab_bronze`, y otra con **Catalog** = `s3tablescatalog/lkh-lab-tables` y **Database** = `silver`. **Muestra** que lo único que cambia es el *Catalog*: Bronze vive en el Glue Data Catalog y Silver en S3 Tables.

```sql
SELECT estado, count(*) AS n FROM siniestros GROUP BY estado;
SELECT count(*) - count(DISTINCT id_siniestro) AS duplicados FROM siniestros;
SHOW TBLPROPERTIES clientes;
```

✅ **Verificación para todos:** 3 estados y `duplicados = 0`.

🛟 **Si alguien se perdió:** `./lab.sh 2`. Corre el mismo job y antes revisa la configuración: si el error fue de un parámetro, dice cuál.

🔥 **Si falla en vivo:**

| Síntoma | Qué hacer |
|---|---|
| `AccessDenied` sobre `s3tables` | El ARN del job o el de la política no coincide. Corre `./lab.sh 2` en tu CloudShell: te dice cuál está mal |
| Missing argument / `KeyError` | Falta un `--` en un parámetro |
| El job tarda más de 6 minutos | Sigue la demo en el entorno de respaldo (`s3tablescatalog/lkh-bkp-tables`) y vuelve a tu job al final |

---

## Lab 3 · Gold · 12 min

🎯 **Qué demuestras:** que Gold responde **preguntas de negocio**, y que ahí ya no hay datos personales.

🖥️ **Pantallas:**
1. **Glue → `lkh-lab-job-silver-to-gold` → Run** (~3 min).
2. Mientras corre: slide de la fórmula de siniestralidad.
3. **S3 Tables → `gold`**: las 3 tablas `agg_*`.
   **Di:** "El prefijo `agg_` dice que son agregadas: el nombre explica la tabla."
4. **Athena → base `gold`** → la consulta de siniestralidad.

⏳ **Mientras esperas:**
- **Siniestralidad = siniestros pagados ÷ primas cobradas.** "Es el indicador que mira toda gerencia técnica de seguros. Arriba de 70–80 %, el producto probablemente pierde dinero."
- **Gold solo lee Silver**, nunca Bronze.
- **`agg_cartera_region_producto`** agrega por departamento: "no hay forma de identificar a una persona".

⭐ **Momento clave:** **SALUD 2025 con 87.8 %**. "De cada 100 soles que cobramos, pagamos casi 88 en siniestros." Pregunta: **"¿Qué le recomendarían a la gerencia?"**

```sql
SELECT producto, anio, primas_cobradas, siniestros_pagados, ratio_siniestralidad
FROM agg_siniestralidad_producto_anual
ORDER BY anio DESC, ratio_siniestralidad DESC;
```

✅ **Verificación para todos:** SALUD encabeza 2025 con 0.878.

🛟 **Si alguien se perdió:** `./lab.sh 3`. Si le falta Silver, el script se lo dice; con `./deploy.sh --hasta gold` alcanza las dos de una vez.

🔥 **Si falla en vivo:** `Table not found: silver.siniestros` significa que el Lab 2 no terminó. Revisa *Runs* del job de Silver.

---

## Lab 4 · Auditoría y time travel · 15 min ⭐

🎯 **Qué demuestras:** las tres capacidades que separan un Lakehouse de un data lake: **evolución de esquema, cambios por fila y time travel**. Es el momento más fuerte del workshop: no lo apures.

🖥️ **Pantallas:**
1. **Cuenta la historia (1 min):** "Prevención de fraude detecta que el siniestro SIN-00042, un robo de 18,500 soles ya pagado, era fraude."
2. **Athena →** base `silver`: el estado actual y la hora.
   ```sql
   SELECT id_siniestro, estado, monto_pagado FROM siniestros WHERE id_siniestro = 'SIN-00042';
   SELECT current_timestamp;
   ```
   **Di:** "Anoten esta hora: la vamos a necesitar en 5 minutos."
3. **Glue → `lkh-lab-job-silver-auditoria` → pestaña Script** → muestra las tres sentencias: `ALTER TABLE`, `UPDATE`, `VERSION AS OF`. → **Run**.
4. Cuando termine: la ejecución → **Output logs** (CloudWatch) → el **ANTES** y el **AHORA** impresos por el job.
5. **Athena →** las tres consultas de abajo, **en este orden**.

⏳ **Mientras esperas:**
- **`ALTER TABLE ... ADD COLUMN`:** "Solo cambia metadatos: no reescribe ni un archivo, y nadie que consulte la tabla se entera."
- **`UPDATE`:** "En un data lake de solo archivos, esto es reescribir particiones completas. En Iceberg es una transacción."
- **Snapshots:** "Cada cambio crea una versión nueva. La anterior sigue ahí."

⭐ **Momento clave:** la consulta de **antes**. Cambia la hora por la que anotaste. Di: **"Seis meses después llega el auditor y pregunta: ¿cómo estaba este siniestro antes de que lo corrigieran? Respuesta: una línea de SQL."**

```sql
-- 1. Hoy
SELECT id_siniestro, estado, monto_pagado, flag_fraude
FROM siniestros WHERE id_siniestro = 'SIN-00042';

-- 2. El auditor pregunta: ¿cómo estaba antes?
SELECT id_siniestro, estado, monto_pagado
FROM siniestros FOR TIMESTAMP AS OF TIMESTAMP 'AAAA-MM-DD HH:MM:SS UTC'
WHERE id_siniestro = 'SIN-00042';

-- 3. Toda la historia de la tabla
SELECT * FROM "siniestros$history";
```

✅ **Verificación para todos:** hoy `RECHAZADO · 0.00 · true`; antes `PAGADO · 17250.00`.

🛟 **Si alguien se perdió:** `./lab.sh 4`. Al terminar, imprime la consulta de time travel con la hora exacta, lista para copiar.

🔥 **Si falla en vivo:**

| Síntoma | Qué hacer |
|---|---|
| El time travel devuelve el valor nuevo | La hora es posterior al `UPDATE` o no está en UTC: usa la que devolvió `current_timestamp` |
| El time travel da error | La hora es anterior a la creación de la tabla. Usa `FOR VERSION AS OF <snapshot_id>` con el primer id de `siniestros$history` |

---

## Lab 5 · Gobierno (demo) · 6 min

🎯 **Qué demuestras:** que la **misma tabla** muestra cosas distintas según el rol, definido en un solo lugar.

> Esta demo **se prepara antes del evento** en tu cuenta. Configurar Lake Formation sobre `s3tablescatalog` cambia la configuración de toda la cuenta, así que no se hace en vivo ni en las cuentas de los asistentes. Los pasos están en [labs/lab5-gobierno](lab5-gobierno/README.md).

🖥️ **Pantallas:**
1. **Lake Formation → Data permissions:** muestra el permiso de `analista-riesgos` sobre `silver.clientes`, que solo incluye `id_cliente` y `departamento`.
2. **Switch role** a `analista-riesgos` → **Athena:** `SELECT * FROM silver.clientes LIMIT 5;` → solo ve las columnas permitidas.
3. `SELECT * FROM gold.agg_cartera_region_producto LIMIT 5;` → funciona normal.

⭐ **Momento clave:** la misma consulta, dos roles, dos resultados. **"Esto es lo que pide el oficial de protección de datos."**

🔥 **Si falla en vivo:** ten **capturas de pantalla** de los dos resultados en el deck. Esta es la demo con más riesgo de permisos.

---

## Cierre · Limpieza y preguntas · 12 min

🖥️ **Pantallas:**
1. **CloudShell → `./cleanup.sh`**: aunque todo se creó a mano, el script lo encuentra por los nombres del estándar y lo borra en el orden correcto (*modo huérfanos*).
   **Di:** "La limpieza manual son 8 pasos en orden. Con código, uno."
2. Slides de costos, del CV y de siguientes pasos.

⭐ **Momento clave:** comparar las dos rutas. "Hoy lo hicimos a mano para entender cada pieza. En una empresa esto se hace con código: `./deploy.sh --entorno prd`."

✅ **Verificación para todos:** `./lab.sh estado` → *"Origen: todavia no hay nada creado"*.

🛟 **Recuerda:** si desplegaste el respaldo, `./cleanup.sh --entorno bkp`.
