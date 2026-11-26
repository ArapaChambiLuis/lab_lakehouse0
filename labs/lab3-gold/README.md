# Lab 3 · Gold

## 🎯 Objetivo
Construir las tablas que consume el negocio. Aquí la pregunta ya no es técnica: **¿qué producto nos está haciendo perder plata?**

## 👀 Antes de ejecutar: el indicador clave
La **siniestralidad** es el indicador que mira toda gerencia técnica de seguros:

```
siniestralidad = siniestros pagados / primas cobradas
```

Si pasa de ~70–80%, ese producto probablemente pierde dinero, porque además hay gastos de operación y comisiones.

Abre `glue/silver_to_gold.py`. Crea 3 tablas:

| Tabla | Para quién |
|---|---|
| `agg_siniestralidad_producto_anual` | Gerencia técnica: ratio por producto y año |
| `agg_siniestros_producto_mensual` | Dashboard de operaciones: evolución mes a mes |
| `agg_cartera_region_producto` | Comercial: pólizas y primas por departamento, **sin datos personales** |

Nomenclatura Gold: `{tipo}_{tema}_{granularidad}`. El prefijo `agg_` indica una tabla agregada; si el modelo crece, vendrían `fct_` (hechos) y `dim_` (dimensiones).

## ▶️ Ejecutar
```bash
./lab.sh 3
```

## 🔍 Qué pasó por detrás
- Gold se construye **solo desde Silver**, nunca desde Bronze.
- Las tablas se recrean completas en cada ejecución (`createOrReplace`). Con volúmenes grandes se usaría `MERGE INTO` incremental.
- Ninguna tabla de Gold tiene DNI, nombre ni email: el analista trabaja aquí sin tocar PII.

## ✅ Verificar en la consola
**Athena** → catálogo `s3tablescatalog/lkh-lab-tables` → base `gold`:

```sql
-- ¿Qué producto tiene la peor siniestralidad?
SELECT producto, anio, primas_cobradas, siniestros_pagados, ratio_siniestralidad
FROM agg_siniestralidad_producto_anual
ORDER BY anio DESC, ratio_siniestralidad DESC;

-- ¿En qué departamentos se concentra la cartera?
SELECT departamento, sum(prima_anual_total) AS prima
FROM agg_cartera_region_producto
GROUP BY departamento ORDER BY prima DESC;
```

## 💬 Para pensar
- Mira el producto SALUD: ¿qué le recomendarías a la gerencia?
- ¿Qué otra tabla Gold pedirían en tu empresa? Intenta agregarla en `glue/silver_to_gold.py` y vuelve a ejecutar `./lab.sh 3`.

➡️ Siguiente: [Lab 4 · Auditoría](../lab4-auditoria/README.md)
