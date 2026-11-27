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
En **Athena → Query editor** hay cuatro controles, en dos lugares:

| Control | Dónde está | Qué eliges |
|---|---|---|
| **Workgroup** | Arriba a la **derecha** (dice `primary` por defecto) | `lkh-lab-wg-analistas` |
| **Data source** | Panel **izquierdo** (sección *Data*), primer campo | `AwsDataCatalog` (viene por defecto) |
| **Catalog** | Panel izquierdo, segundo campo | `None`. En el Lab 2 aquí eliges `s3tablescatalog/lkh-lab-tables` |
| **Database** | Panel izquierdo, tercer campo | `lkh_lab_bronze`. Si no aparece, refresca con ↻ |

> 💡 **Atajo:** lo único obligatorio es el **workgroup**. Como las consultas usan el nombre completo (`lkh_lab_bronze.siniestros`), funcionan aunque en el panel esté elegida otra base.

Ejecuta:

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

### 🎯 Resultados esperados

Con los datos del repo, todos deben ver exactamente esto:

| Consulta | Resultado |
|---|---|
| Estados de siniestro | **9 formas** de escribir 3 estados: `PAGADO` 667, `EN_EVALUACION` 221, `RECHAZADO` 212, `pagado` 44, `  Pagado ` 19, `en_evaluacion` 18, `rechazado` 14, `  En_Evaluacion ` 8, `  Rechazado ` 4 (1,207 filas en total) |
| Siniestros que llegaron más de una vez | **38** |
| Pólizas de clientes que no existen | **5** (todas del cliente `CLI-99999`) |

Además, `SELECT count(*), count(DISTINCT id_cliente) FROM lkh_lab_bronze.clientes` da **2,040 filas para 2,000 clientes**: hay clientes duplicados.

## 💬 Para pensar
- Si un analista arma un reporte de siniestralidad directo desde Bronze, ¿qué número le daría a la gerencia?
- ¿Dónde aparecen estos mismos errores en los sistemas de tu empresa?

➡️ Siguiente: [Lab 2 · Silver](../lab2-silver/README.md)
