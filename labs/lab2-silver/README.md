# Lab 2 · Silver

## 🎯 Objetivo
Convertir los CSV crudos en **tablas Apache Iceberg confiables** en Amazon S3 Tables: tipadas, sin duplicados y con integridad referencial.

## 👀 Antes de ejecutar: lee el código
Abre `glue/bronze_to_silver.py` (en CloudShell: `cat glue/bronze_to_silver.py`) y ubica estas partes:

| Bloque | Qué resuelve |
|---|---|
| `SparkSession.builder ... .type = rest` | Glue se conecta a S3 Tables por su **endpoint Iceberg REST**, sin JARs extra |
| `.dropDuplicates()` en clientes | Elimina los duplicados exactos |
| `limpiar_texto()` | `upper(trim())`: "  pagado " → `PAGADO` |
| `.join(clientes ..., "inner")` en pólizas | Integridad referencial: fuera las pólizas huérfanas |
| `Window ... row_number()` en siniestros | Si un siniestro llegó dos veces, se queda el reporte más reciente |
| `F.abs("monto_pagado")` | Corrige los montos con el signo invertido |
| `dato_incompleto` | No se borra el registro: **se marca**. Así el negocio decide qué hacer con él |
| `partitionedBy(F.months(...))` | Partición oculta de Iceberg: el analista filtra por fecha y no necesita conocer la partición |

## ▶️ Ejecutar
```bash
./lab.sh 2
```
El job de Glue tarda ~3–5 minutos (incluye el arranque del clúster serverless). Mientras corre, vuelve al código.

## 🔍 Qué pasó por detrás
- Glue 5.0 leyó Bronze, aplicó las reglas y escribió 4 tablas en el namespace `silver`.
- Cada escritura es una **transacción ACID**: si el job falla a la mitad, la tabla anterior sigue intacta.
- S3 Tables se encarga del mantenimiento por ti: compactación de archivos pequeños y limpieza de snapshots viejos.

## ✅ Verificar en la consola
En **Athena → Query editor**, con el workgroup `lkh-lab-wg-analistas` (arriba a la derecha), en el panel izquierdo elige **Data source** = `AwsDataCatalog`, **Catalog** = `s3tablescatalog/lkh-lab-tables` y **Database** = `silver`.

> 💡 **Atajo:** si no encuentras el campo **Catalog**, escribe el nombre completo en la consulta: `FROM "s3tablescatalog/lkh-lab-tables"."silver"."siniestros"`.

```sql
-- Ahora solo hay 3 estados limpios
SELECT estado, count(*) AS n FROM siniestros GROUP BY estado;

-- Cero duplicados
SELECT count(*) - count(DISTINCT id_siniestro) AS duplicados FROM siniestros;

-- Registros marcados para revisión
SELECT count(*) AS incompletos FROM siniestros WHERE dato_incompleto;
```

Compara los conteos con los de Bronze. ¿Cuántas filas se fueron y por qué?

En **S3** → *Table buckets* → `lkh-lab-tables` → `silver` puedes ver las tablas creadas.

## 💬 Para pensar
- ¿Por qué marcar `dato_incompleto` en lugar de borrar la fila?
- Si mañana llegan 10 millones de siniestros, ¿qué cambiarías? (Pista: `NumberOfWorkers` del job y la partición.)

➡️ Siguiente: [Lab 3 · Gold](../lab3-gold/README.md)
