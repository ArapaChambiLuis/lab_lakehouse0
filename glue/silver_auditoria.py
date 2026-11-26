"""
Lab 4 - Job silver-auditoria: escalabilidad y auditoria
1. Evolucion de esquema: agrega la columna flag_fraude a silver.siniestros
   sin reescribir datos ni romper a quien ya consulta la tabla.
2. Correccion: el siniestro SIN-00042 resulta ser fraude -> se anula el pago.
3. Time travel: muestra el antes y el despues usando los snapshots de Iceberg.

Parametros del job: --TABLE_BUCKET_ARN  --AWS_REGION_NAME
"""
import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession

args = getResolvedOptions(sys.argv, ["TABLE_BUCKET_ARN", "AWS_REGION_NAME"])
REGION = args["AWS_REGION_NAME"]
CAT = "lh"
TABLA = f"{CAT}.silver.siniestros"
ID = "SIN-00042"

spark = (
    SparkSession.builder.appName("job-silver-auditoria")
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

snapshot_antes = spark.sql(
    f"SELECT snapshot_id FROM {TABLA}.snapshots ORDER BY committed_at DESC LIMIT 1"
).first()["snapshot_id"]
print(f"[lab4] snapshot antes del cambio: {snapshot_antes}")

# 1) Evolucion de esquema (idempotente: si ya existe, no hace nada)
if "flag_fraude" not in spark.table(TABLA).columns:
    spark.sql(f"ALTER TABLE {TABLA} ADD COLUMN flag_fraude BOOLEAN")
    print("[lab4] columna flag_fraude agregada")

# 2) Correccion del siniestro (UPDATE fila a fila, con transaccion ACID)
spark.sql(f"""
    UPDATE {TABLA}
    SET estado = 'RECHAZADO', monto_pagado = 0, flag_fraude = true
    WHERE id_siniestro = '{ID}'
""")

# 3) Time travel: el auditor pregunta "como estaba antes?"
cols = "id_siniestro, estado, monto_pagado"
print("[lab4] ANTES (time travel):")
spark.sql(f"SELECT {cols} FROM {TABLA} VERSION AS OF {snapshot_antes} WHERE id_siniestro = '{ID}'").show()
print("[lab4] AHORA:")
spark.sql(f"SELECT {cols}, flag_fraude FROM {TABLA} WHERE id_siniestro = '{ID}'").show()
print("[lab4] historial de snapshots:")
spark.sql(f"SELECT committed_at, snapshot_id, operation FROM {TABLA}.snapshots ORDER BY committed_at").show(truncate=False)
print("[lab4] listo")
