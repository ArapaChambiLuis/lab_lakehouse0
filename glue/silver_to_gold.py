"""
Lab 3 - Job silver-to-gold
Construye las tablas de negocio a partir de Silver, en el namespace "gold"
de Amazon S3 Tables. Nada de PII llega a Gold: el analista trabaja aqui.

Parametros del job: --TABLE_BUCKET_ARN  --AWS_REGION_NAME
"""
import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession

args = getResolvedOptions(sys.argv, ["TABLE_BUCKET_ARN", "AWS_REGION_NAME"])
REGION = args["AWS_REGION_NAME"]
CAT = "lh"

spark = (
    SparkSession.builder.appName("job-silver-to-gold")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config(f"spark.sql.catalog.{CAT}", "org.apache.iceberg.spark.SparkCatalog")
    .config(f"spark.sql.catalog.{CAT}.type", "rest")
    .config(f"spark.sql.catalog.{CAT}.uri", f"https://s3tables.{REGION}.amazonaws.com/iceberg")
    .config(f"spark.sql.catalog.{CAT}.warehouse", args["TABLE_BUCKET_ARN"])
    .config(f"spark.sql.catalog.{CAT}.rest.sigv4-enabled", "true")
    .config(f"spark.sql.catalog.{CAT}.rest.signing-name", "s3tables")
    .config(f"spark.sql.catalog.{CAT}.rest.signing-region", REGION)
    .config(f"spark.sql.catalog.{CAT}.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
    .getOrCreate()
)

# Nomenclatura Gold: {tipo}_{tema}_{granularidad}. agg_ = tabla agregada.
GOLD = {
    # Siniestralidad = siniestros pagados / primas cobradas, por producto y anio.
    # Es EL indicador que mira la gerencia tecnica de una aseguradora.
    "agg_siniestralidad_producto_anual": f"""
        WITH primas AS (
            SELECT p.producto, year(g.fecha_pago) AS anio, sum(g.monto) AS primas_cobradas
            FROM {CAT}.silver.pagos_primas g
            JOIN {CAT}.silver.polizas p ON p.id_poliza = g.id_poliza
            GROUP BY p.producto, year(g.fecha_pago)
        ),
        sin AS (
            SELECT p.producto, year(s.fecha_siniestro) AS anio,
                   count(*) AS n_siniestros,
                   sum(s.monto_pagado) AS siniestros_pagados
            FROM {CAT}.silver.siniestros s
            JOIN {CAT}.silver.polizas p ON p.id_poliza = s.id_poliza
            GROUP BY p.producto, year(s.fecha_siniestro)
        )
        SELECT pr.producto, pr.anio,
               CAST(pr.primas_cobradas AS DECIMAL(14,2)) AS primas_cobradas,
               coalesce(sin.n_siniestros, 0) AS n_siniestros,
               CAST(coalesce(sin.siniestros_pagados, 0) AS DECIMAL(14,2)) AS siniestros_pagados,
               CAST(coalesce(sin.siniestros_pagados, 0) / pr.primas_cobradas AS DECIMAL(6,4)) AS ratio_siniestralidad
        FROM primas pr
        LEFT JOIN sin ON sin.producto = pr.producto AND sin.anio = pr.anio
    """,
    # Evolucion mensual para un dashboard.
    "agg_siniestros_producto_mensual": f"""
        SELECT date_trunc('MONTH', s.fecha_siniestro) AS mes,
               p.producto,
               count(*) AS n_siniestros,
               CAST(sum(s.monto_reclamado) AS DECIMAL(14,2)) AS monto_reclamado,
               CAST(sum(s.monto_pagado) AS DECIMAL(14,2)) AS monto_pagado,
               sum(CASE WHEN s.estado = 'RECHAZADO' THEN 1 ELSE 0 END) AS n_rechazados
        FROM {CAT}.silver.siniestros s
        JOIN {CAT}.silver.polizas p ON p.id_poliza = s.id_poliza
        GROUP BY date_trunc('MONTH', s.fecha_siniestro), p.producto
    """,
    # Cartera por region SIN datos personales (ni DNI, ni nombre, ni email).
    "agg_cartera_region_producto": f"""
        SELECT c.departamento, p.producto,
               count(DISTINCT p.id_poliza) AS n_polizas,
               count(DISTINCT c.id_cliente) AS n_clientes,
               CAST(sum(p.prima_anual) AS DECIMAL(14,2)) AS prima_anual_total
        FROM {CAT}.silver.polizas p
        JOIN {CAT}.silver.clientes c ON c.id_cliente = p.id_cliente
        WHERE p.estado = 'VIGENTE'
        GROUP BY c.departamento, p.producto
    """,
}

for tabla, sql in GOLD.items():
    destino = f"{CAT}.gold.{tabla}"
    df = spark.sql(sql)
    columnas = ", ".join(f"`{c.name}` {c.dataType.simpleString()}" for c in df.schema.fields)
    # Mismo patron que en bronze_to_silver.py: CREATE TABLE con esquema
    # explicito + append(), porque S3 Tables no soporta el "staged create"
    # que usa cualquier CTAS de Iceberg (create() y createOrReplace()).
    spark.sql(f"DROP TABLE IF EXISTS {destino}")
    spark.sql(f"""
        CREATE TABLE {destino} ({columnas})
        USING iceberg
        TBLPROPERTIES ('format-version' = '2', 'clasificacion' = 'interna')
    """)
    df.writeTo(destino).append()
    print(f"[gold] {destino}: {spark.table(destino).count()} filas")

print("[gold] listo")
