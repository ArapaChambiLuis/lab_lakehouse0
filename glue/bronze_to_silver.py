"""
Lab 2 - Job bronze-to-silver
Lee los CSV crudos de Bronze (S3), los limpia y escribe tablas Apache Iceberg
en Amazon S3 Tables (namespace "silver").

Se conecta a S3 Tables por su endpoint Iceberg REST, asi que no necesita JARs
extra: basta con Glue 5.0 y --datalake-formats iceberg.

Parametros del job: --RAW_BUCKET  --TABLE_BUCKET_ARN  --AWS_REGION_NAME
"""
import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ["RAW_BUCKET", "TABLE_BUCKET_ARN", "AWS_REGION_NAME"])
REGION = args["AWS_REGION_NAME"]
CAT = "lh"  # nombre corto del catalogo Iceberg dentro de Spark

spark = (
    SparkSession.builder.appName("job-bronze-to-silver")
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

BRONZE = f"s3://{args['RAW_BUCKET']}/bronze"


def leer_csv(tabla):
    # Todo entra como string: en Bronze no se confia en los tipos.
    return spark.read.option("header", "true").option("inferSchema", "false").csv(f"{BRONZE}/{tabla}/")


def limpiar_texto(col):
    return F.upper(F.trim(F.col(col)))


def ddl_columnas(df):
    """Esquema del DataFrame como lista de columnas para un CREATE TABLE."""
    return ", ".join(f"`{c.name}` {c.dataType.simpleString()}" for c in df.schema.fields)


def escribir(df, tabla, particion=None, clasificacion="interna"):
    """Crea la tabla Iceberg y le inserta el DataFrame.

    Ojo con el patron, que es la parte que mas se equivoca con S3 Tables:
    NO se puede usar writeTo(...).create() ni .createOrReplace(). El
    SparkCatalog de Iceberg implementa StagingTableCatalog, asi que Spark
    manda cualquier CTAS por el plan atomico (AtomicCreateTableAsSelectExec),
    que pide un "staged create" al catalogo. S3 Tables no lo soporta y
    responde "Malformed request: Stage-create is currently not supported".

    La via que si funciona: CREATE TABLE con el esquema explicito (no es un
    CTAS, no pasa por staging) y despues append().
    """
    destino = f"{CAT}.silver.{tabla}"
    particionado = f"PARTITIONED BY ({particion})" if particion else ""
    spark.sql(f"DROP TABLE IF EXISTS {destino}")
    # La clasificacion de la informacion viaja con la tabla como propiedad
    # Iceberg: se ve con SHOW TBLPROPERTIES.
    spark.sql(f"""
        CREATE TABLE {destino} ({ddl_columnas(df)})
        USING iceberg
        {particionado}
        TBLPROPERTIES ('format-version' = '2', 'clasificacion' = '{clasificacion}')
    """)
    df.writeTo(destino).append()
    print(f"[silver] {destino}: {spark.table(destino).count()} filas")


# ---------------- clientes ----------------
clientes = (
    leer_csv("clientes")
    .dropDuplicates()  # duplicados exactos
    .select(
        F.trim("id_cliente").alias("id_cliente"),
        F.trim("dni").alias("dni"),
        F.initcap(F.trim("nombre")).alias("nombre"),
        F.lower(F.trim("email")).alias("email"),
        limpiar_texto("departamento").alias("departamento"),
        F.to_date("fecha_nacimiento").alias("fecha_nacimiento"),
    )
    .dropDuplicates(["id_cliente"])
)
escribir(clientes, "clientes", clasificacion="confidencial")  # PII: dni, nombre, email

# ---------------- polizas ----------------
polizas = (
    leer_csv("polizas")
    .select(
        F.trim("id_poliza").alias("id_poliza"),
        F.trim("id_cliente").alias("id_cliente"),
        limpiar_texto("producto").alias("producto"),
        F.to_date("fecha_inicio").alias("fecha_inicio"),
        F.to_date("fecha_fin").alias("fecha_fin"),
        F.col("prima_anual").cast("decimal(12,2)").alias("prima_anual"),
        limpiar_texto("estado").alias("estado"),
    )
    # integridad referencial: fuera las polizas de clientes que no existen
    .join(clientes.select("id_cliente"), "id_cliente", "inner")
    .dropDuplicates(["id_poliza"])
)
escribir(polizas, "polizas", "producto")

# ---------------- pagos de primas ----------------
pagos = (
    leer_csv("pagos_primas")
    .select(
        F.trim("id_pago").alias("id_pago"),
        F.trim("id_poliza").alias("id_poliza"),
        F.to_date("fecha_pago").alias("fecha_pago"),
        F.col("monto").cast("decimal(12,2)").alias("monto"),
        limpiar_texto("medio_pago").alias("medio_pago"),
    )
    .join(polizas.select("id_poliza"), "id_poliza", "inner")
    .dropDuplicates(["id_pago"])
)
escribir(pagos, "pagos_primas", "years(fecha_pago)")

# ---------------- siniestros ----------------
crudo = leer_csv("siniestros").select(
    F.trim("id_siniestro").alias("id_siniestro"),
    F.trim("id_poliza").alias("id_poliza"),
    F.to_date("fecha_siniestro").alias("fecha_siniestro"),
    F.to_date("fecha_reporte").alias("fecha_reporte"),
    limpiar_texto("causa").alias("causa"),
    F.col("monto_reclamado").cast("decimal(12,2)").alias("monto_reclamado"),
    F.col("monto_pagado").cast("decimal(12,2)").alias("monto_pagado"),
    limpiar_texto("estado").alias("estado"),
)
# Si un siniestro llego dos veces, nos quedamos con el reporte mas reciente.
ultima_version = Window.partitionBy("id_siniestro").orderBy(F.col("fecha_reporte").desc())
siniestros = (
    crudo.withColumn("_rn", F.row_number().over(ultima_version))
    .filter("_rn = 1")
    .drop("_rn")
    # reglas de calidad
    .withColumn("monto_pagado", F.abs("monto_pagado"))  # negativos = error de signo
    .withColumn("dato_incompleto", F.col("monto_reclamado").isNull())
    .join(polizas.select("id_poliza"), "id_poliza", "inner")
)
escribir(siniestros, "siniestros", "months(fecha_siniestro)")

print("[silver] listo")
