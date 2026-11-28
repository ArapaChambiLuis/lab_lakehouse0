# Lab 4 · Escalabilidad y auditoría ⭐

## 🎯 Objetivo
Ver las tres capacidades que separan un Lakehouse de un data lake común: **evolución de esquema**, **cambios a nivel de fila** y **time travel**.

## 📖 La historia
El área de prevención de fraude detecta que el siniestro **SIN-00042** (un robo de 18,500 soles, ya pagado) era fraudulento. Hay que:
1. Agregar a la tabla un campo nuevo, `flag_fraude`, que antes no existía.
2. Corregir el registro: estado `RECHAZADO` y monto pagado en 0.
3. Seis meses después, el auditor de la SBS pregunta: **"¿cómo estaba ese siniestro antes de la corrección?"**

En un data lake de solo archivos, esto implica reescribir particiones completas y cruzar los dedos. En Iceberg son tres sentencias.

## 👀 Antes de ejecutar
Primero mira el siniestro **antes** del cambio. En **Athena**, con el catálogo `s3tablescatalog/lkh-lab-tables` y la base `silver`:

```sql
SELECT id_siniestro, estado, monto_pagado FROM siniestros WHERE id_siniestro = 'SIN-00042';
-- Historial de snapshots actual
SELECT * FROM "siniestros$history";
```

Luego abre `glue/silver_auditoria.py`: `ALTER TABLE ... ADD COLUMN`, `UPDATE` y `VERSION AS OF`.

## ▶️ Ejecutar
```bash
./lab.sh 4
```
Al final, el script imprime el **AHORA** y el **ANTES**, y te deja una consulta de time travel lista para copiar.

## 🔍 Qué pasó por detrás
- `ADD COLUMN` solo cambió los **metadatos**: no se reescribió ningún archivo, y las consultas anteriores siguen funcionando.
- `UPDATE` creó un **snapshot nuevo**. El anterior sigue existiendo.
- Time travel consulta ese snapshot anterior por fecha (`FOR TIMESTAMP AS OF`) o por id (`FOR VERSION AS OF`).

## ✅ Verificar en la consola
```sql
-- Hoy
SELECT id_siniestro, estado, monto_pagado, flag_fraude
FROM siniestros WHERE id_siniestro = 'SIN-00042';

-- Antes (pega la hora UTC que imprimió ./lab.sh 4)
SELECT id_siniestro, estado, monto_pagado
FROM siniestros FOR TIMESTAMP AS OF TIMESTAMP 'AAAA-MM-DD HH:MM:SS UTC'
WHERE id_siniestro = 'SIN-00042';

-- El historial ahora tiene un snapshot más
SELECT * FROM "siniestros$history";
```

## 💬 Para pensar
- S3 Tables borra los snapshots viejos según su política de retención. ¿Cuánto tiempo pide guardar historia el regulador en tu sector? ¿Cómo lo configurarías?
- ¿Qué otros casos de tu trabajo se resolverían con time travel? (Reprocesos, cierres contables, reclamos de clientes...)

➡️ Siguiente: [Lab 5 · Gobierno](../lab5-gobierno/README.md)
