# Lab 1 · Bronze

## 🎯 Objetivo
Guardar los datos **tal como llegaron** del core de seguros y descubrir sus problemas antes de limpiarlos.

> Regla de Bronze: no se corrige nada. Si mañana descubres un error en tu limpieza, necesitas el dato original para reprocesar.

## ▶️ Ejecutar
```bash
./lab.sh 1
```

## 🔍 Qué pasó por detrás
1. `data/generator.py` creó 4 archivos CSV de **Aseguradora Andina S.A.**: `clientes`, `polizas`, `pagos_primas` y `siniestros`.
2. Se subieron a `s3://<tu-bucket>/bronze/<tabla>/`.
3. `sql/bronze_ddl.sql` creó tablas externas en Athena. **Todas las columnas son `string`**: en Bronze no se confía en los tipos.

Los datos traen errores a propósito, como en la vida real:

| Problema | Ejemplo |
|---|---|
| Mayúsculas y espacios inconsistentes | `PAGADO`, `pagado`, `  Pagado ` |
| Siniestros reenviados | El mismo `id_siniestro` dos veces, con distinta `fecha_reporte` |
| Montos nulos y negativos | `monto_reclamado` vacío, `monto_pagado` = `-1520.30` |
| Pólizas huérfanas | Apuntan al cliente `CLI-99999`, que no existe |
| Clientes duplicados | Filas idénticas |

## ✅ Verificar en la consola
Abre **Athena** → workgroup `lkh-lab-wg-analistas` → catálogo `AwsDataCatalog` → base `lkh_lab_bronze`, y ejecuta:

```sql
-- ¿Cuántas formas distintas de escribir "PAGADO" hay?
SELECT estado, count(*) AS n
FROM lkh_lab_bronze.siniestros
GROUP BY estado ORDER BY n DESC;

-- Siniestros que llegaron más de una vez
SELECT id_siniestro, count(*) AS veces
FROM lkh_lab_bronze.siniestros
GROUP BY id_siniestro HAVING count(*) > 1;

-- Pólizas de clientes que no existen
SELECT p.id_poliza, p.id_cliente
FROM lkh_lab_bronze.polizas p
LEFT JOIN lkh_lab_bronze.clientes c ON c.id_cliente = p.id_cliente
WHERE c.id_cliente IS NULL;
```

Mira el dato **"Data scanned"** debajo de cada resultado: solo son KB. Así se calcula el costo en Athena.

## 💬 Para pensar
- Si un analista arma un reporte de siniestralidad directo desde Bronze, ¿qué número le daría a la gerencia?
- ¿Dónde aparecen estos mismos errores en los sistemas de tu empresa?

➡️ Siguiente: [Lab 2 · Silver](../lab2-silver/README.md)
