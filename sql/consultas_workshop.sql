-- Consultas para correr en la consola de Athena durante el workshop.
-- Workgroup (arriba a la derecha): lkh-lab-wg-analistas
-- Panel izquierdo (seccion Data), segun la capa:
--   Bronze:      Data source = AwsDataCatalog, Catalog = None,                          Database = lkh_lab_bronze
--   Silver/Gold: Data source = AwsDataCatalog, Catalog = s3tablescatalog/lkh-lab-tables, Database = silver o gold

---------------------------------------------------------------
-- LAB 1 (Bronze) - Data source AwsDataCatalog, Catalog None, Database lkh_lab_bronze
---------------------------------------------------------------
-- La suciedad que vamos a limpiar:
SELECT estado, count(*) AS n
FROM lkh_lab_bronze.siniestros
GROUP BY estado ORDER BY n DESC;          -- "PAGADO", "pagado", " Pagado " ...

SELECT id_siniestro, count(*) AS veces
FROM lkh_lab_bronze.siniestros
GROUP BY id_siniestro HAVING count(*) > 1; -- reenvios duplicados

---------------------------------------------------------------
-- LAB 2 (Silver) - base silver
---------------------------------------------------------------
SELECT estado, count(*) AS n FROM silver.siniestros GROUP BY estado;
SELECT count(*) AS incompletos FROM silver.siniestros WHERE dato_incompleto;

---------------------------------------------------------------
-- LAB 3 (Gold) - base gold
---------------------------------------------------------------
-- Que producto nos esta haciendo perder plata?
SELECT producto, anio, primas_cobradas, siniestros_pagados, ratio_siniestralidad
FROM gold.agg_siniestralidad_producto_anual
ORDER BY anio DESC, ratio_siniestralidad DESC;

SELECT * FROM gold.agg_cartera_region_producto ORDER BY prima_anual_total DESC LIMIT 10;

---------------------------------------------------------------
-- LAB 4 (time travel) - despues de correr ./lab.sh 4
---------------------------------------------------------------
-- Historial de cambios de la tabla
SELECT * FROM silver."siniestros$history";

-- Como esta hoy
SELECT id_siniestro, estado, monto_pagado, flag_fraude
FROM silver.siniestros WHERE id_siniestro = 'SIN-00042';

-- Como estaba antes (cambia la hora por una anterior a la ejecucion del lab4, en UTC)
SELECT id_siniestro, estado, monto_pagado
FROM silver.siniestros FOR TIMESTAMP AS OF TIMESTAMP '2026-01-01 00:00:00 UTC'
WHERE id_siniestro = 'SIN-00042';
