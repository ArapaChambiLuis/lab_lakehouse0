#!/usr/bin/env python3
"""
Pruebas de LOGICA de los jobs de Glue: corre los scripts de glue/ de verdad,
con PySpark local, sobre los CSV de data/sample/, y revisa el resultado.

Dos modos:
  --iceberg   Iceberg real (catalogo local tipo hadoop). Ejecuta los 3 jobs,
              incluido el Lab 4: ALTER TABLE, UPDATE, snapshots y time travel.
              Necesita descargar iceberg-spark-runtime de Maven (lo hace la CI).
  (sin flag)  Simulado: sin Iceberg, las tablas son vistas temporales. Prueba
              la limpieza de Silver y los KPIs de Gold; el Lab 4 se omite.

No se conecta a AWS: el catalogo REST de S3 Tables se reemplaza por uno local.
Lo que SI es igual que en AWS es el codigo de los scripts, que se ejecuta tal cual.

Uso:  python3 tests/test_logica.py [--iceberg]
"""
import os
import re
import shutil
import sys
import tempfile
import types

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICEBERG = "--iceberg" in sys.argv
ICEBERG_PKG = "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.7.1"

pasan, fallan = 0, 0


def check(cond, msg, detalle=""):
    global pasan, fallan
    if cond:
        pasan += 1
        print(f"   \033[32m✔\033[0m {msg}")
    else:
        fallan += 1
        print(f"   \033[31m✘ {msg}\033[0m" + (f"\n     {detalle}" if detalle else ""))


def seccion(t):
    print(f"\n\033[1m▶ {t}\033[0m", flush=True)


# ---------------- entorno local ----------------
TMP = tempfile.mkdtemp(prefix="lakehouse-test-")
BRONZE = os.path.join(TMP, "bronze")
for t in ("clientes", "polizas", "pagos_primas", "siniestros"):
    os.makedirs(os.path.join(BRONZE, t))
    shutil.copy(os.path.join(RAIZ, "data", "sample", f"{t}.csv"), os.path.join(BRONZE, t))

# awsglue no existe fuera de Glue: lo reemplazamos por uno que entrega los parametros del job
awsglue = types.ModuleType("awsglue")
utils = types.ModuleType("awsglue.utils")
PARAMS = {"RAW_BUCKET": "lkh-lab-raw-local", "AWS_REGION_NAME": "us-east-1",
          "TABLE_BUCKET_ARN": "arn:aws:s3tables:us-east-1:111122223333:bucket/lkh-lab-tables"}
utils.getResolvedOptions = lambda argv, nombres: {n: PARAMS[n] for n in nombres}
awsglue.utils = utils
sys.modules["awsglue"], sys.modules["awsglue.utils"] = awsglue, utils

from pyspark.sql import DataFrame, SparkSession  # noqa: E402

b = (SparkSession.builder.master("local[2]").appName("test-logica")
     .config("spark.ui.enabled", "false").config("spark.sql.shuffle.partitions", "4")
     .config("spark.sql.session.timeZone", "UTC"))
if ICEBERG:
    b = (b.config("spark.jars.packages", ICEBERG_PKG)
         .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
         .config("spark.sql.catalog.lh", "org.apache.iceberg.spark.SparkCatalog")
         .config("spark.sql.catalog.lh.type", "hadoop")
         .config("spark.sql.catalog.lh.warehouse", "file://" + os.path.join(TMP, "warehouse")))
spark = b.getOrCreate()
spark.sparkContext.setLogLevel("ERROR")

PROPS = {}
if ICEBERG:
    # Cargar el catalogo AHORA: cuando el script llame a getOrCreate() con la
    # configuracion de S3 Tables (REST), este catalogo local ya esta en uso.
    spark.sql("CREATE NAMESPACE IF NOT EXISTS lh.silver")
    spark.sql("CREATE NAMESPACE IF NOT EXISTS lh.gold")

    def tabla(nombre):
        return spark.table(f"lh.{nombre}")
else:
    # Sin Iceberg: lh.silver.x -> vista temporal silver__x
    _sql, _table = SparkSession.sql, SparkSession.table

    def _vista(n):
        return n.replace("lh.silver.", "silver__").replace("lh.gold.", "gold__")

    def sql_simulado(self, q, *a, **k):
        s = " ".join(q.split())
        m = re.match(r"DROP TABLE IF EXISTS (lh\.\w+\.\w+)", s)
        if m:
            self.catalog.dropTempView(_vista(m.group(1)))
            return None
        m = re.match(r"CREATE TABLE (lh\.\w+\.\w+) \(.*\) USING iceberg.*TBLPROPERTIES \((.*)\)", s)
        if m:
            PROPS[_vista(m.group(1))] = dict(re.findall(r"'([\w-]+)' = '([^']*)'", m.group(2)))
            return None
        return _sql(self, _vista(q), *a, **k)

    class Escritor:
        def __init__(self, df, nombre):
            self.df, self.nombre = df, _vista(nombre)

        def append(self):
            self.df.cache().createOrReplaceTempView(self.nombre)

    SparkSession.sql = sql_simulado
    SparkSession.table = lambda self, n: _table(self, _vista(n))
    DataFrame.writeTo = lambda self, n: Escritor(self, n)

    def tabla(nombre):
        return spark.table("lh." + nombre)


def correr_job(script):
    fuente = open(os.path.join(RAIZ, "glue", script), encoding="utf-8").read()
    original = "BRONZE = f\"s3://{args['RAW_BUCKET']}/bronze\""
    if original in fuente:
        fuente = fuente.replace(original, f"BRONZE = {BRONZE!r}")
    elif "RAW_BUCKET" in fuente:
        check(False, f"{script}: no encontre la linea BRONZE = ... para apuntar a los CSV locales")
        return
    exec(compile(fuente, script, "exec"), {"__name__": "__main__"})


def filas(df):
    return [r.asDict() for r in df.collect()]


# ======================================================================
seccion(f"Lab 2 · bronze_to_silver.py ({'Iceberg real' if ICEBERG else 'simulado'})")
correr_job("bronze_to_silver.py")
cli, pol, pag, sin = (tabla(f"silver.{t}") for t in ("clientes", "polizas", "pagos_primas", "siniestros"))

n_cli = cli.count()
check(n_cli == cli.select("id_cliente").distinct().count() == 2000, f"clientes sin duplicados (2000, hay {n_cli})")
check(pol.filter("id_cliente = 'CLI-99999'").count() == 0, "polizas huerfanas (CLI-99999) eliminadas")
check(pol.join(cli, "id_cliente", "left_anti").count() == 0, "toda poliza tiene su cliente")
check({r.producto for r in pol.select("producto").distinct().collect()} == {"AUTO", "SOAT", "SALUD", "VIDA", "HOGAR"},
      "productos normalizados en mayusculas")
check(pag.join(pol, "id_poliza", "left_anti").count() == 0, "todo pago tiene su poliza")
check(sin.count() == sin.select("id_siniestro").distinct().count(), "siniestros reenviados deduplicados")
estados = {r.estado for r in sin.select("estado").distinct().collect()}
check(estados == {"PAGADO", "EN_EVALUACION", "RECHAZADO"}, f"estados limpios: {sorted(estados)}")
check(sin.filter("monto_pagado < 0").count() == 0, "sin montos pagados negativos")
check(sin.filter("dato_incompleto").count() == sin.filter("monto_reclamado IS NULL").count() > 0,
      "nulos marcados con dato_incompleto (no borrados)")
s42 = filas(sin.filter("id_siniestro = 'SIN-00042'"))
check(len(s42) == 1 and s42[0]["estado"] == "PAGADO" and float(s42[0]["monto_pagado"]) == 17250.0,
      "SIN-00042 llega PAGADO por 17,250 (protagonista del Lab 4)", f"{s42}")

if ICEBERG:
    def prop(t, k):
        return {r.key: r.value for r in spark.sql(f"SHOW TBLPROPERTIES lh.silver.{t}").collect()}.get(k)
    part = spark.sql("SELECT * FROM lh.silver.siniestros.partitions").count()
    check(part > 12, f"siniestros particionado por mes ({part} particiones)")
else:
    def prop(t, k):
        return PROPS.get(f"silver__{t}", {}).get(k)
check(prop("clientes", "clasificacion") == "confidencial", "silver.clientes clasificada como confidencial (PII)")
check(all(prop(t, "clasificacion") == "interna" for t in ("polizas", "pagos_primas", "siniestros")),
      "el resto de Silver clasificada como interna")
check(prop("siniestros", "format-version") == "2", "tablas Iceberg format-version 2")

# ======================================================================
seccion("Lab 3 · silver_to_gold.py")
correr_job("silver_to_gold.py")
sp = tabla("gold.agg_siniestralidad_producto_anual")
ms = tabla("gold.agg_siniestros_producto_mensual")
cr = tabla("gold.agg_cartera_region_producto")
for nombre, df in (("agg_siniestralidad_producto_anual", sp), ("agg_siniestros_producto_mensual", ms),
                   ("agg_cartera_region_producto", cr)):
    check(df.count() > 0, f"gold.{nombre} tiene filas")
    pii = {"dni", "nombre", "email"} & set(df.columns)
    check(not pii, f"gold.{nombre} sin datos personales", f"columnas PII: {pii}")
mal_ratio = sp.filter("abs(ratio_siniestralidad - siniestros_pagados / primas_cobradas) > 0.0001").count()
check(mal_ratio == 0, "ratio_siniestralidad = siniestros pagados / primas cobradas")
peor = filas(sp.filter("anio = 2025").orderBy("ratio_siniestralidad", ascending=False).limit(1))[0]
check(peor["producto"] == "SALUD" and round(float(peor["ratio_siniestralidad"]), 3) == 0.878,
      f"la peor siniestralidad 2025 es SALUD con 87.8% (la cifra del deck): {peor['producto']} "
      f"{float(peor['ratio_siniestralidad']):.3f}")
vigentes = pol.filter("estado = 'VIGENTE'").count()
check(cr.groupBy().sum("n_polizas").first()[0] == vigentes, f"cartera_region suma las {vigentes} polizas vigentes")
check(ms.groupBy().sum("n_siniestros").first()[0] == sin.count(), "siniestros_mensual cuadra con Silver")

# ======================================================================
if ICEBERG:
    seccion("Lab 4 · silver_auditoria.py (ALTER, UPDATE, snapshots, time travel)")
    snaps_antes = spark.sql("SELECT snapshot_id FROM lh.silver.siniestros.snapshots ORDER BY committed_at").collect()
    total_antes = sin.count()
    correr_job("silver_auditoria.py")
    ahora = filas(spark.sql("SELECT estado, monto_pagado, flag_fraude FROM lh.silver.siniestros "
                            "WHERE id_siniestro = 'SIN-00042'"))[0]
    check(ahora["estado"] == "RECHAZADO" and float(ahora["monto_pagado"]) == 0 and ahora["flag_fraude"] is True,
          f"AHORA: SIN-00042 RECHAZADO, 0, flag_fraude=true ({ahora})")
    antes = filas(spark.sql(f"SELECT estado, monto_pagado FROM lh.silver.siniestros VERSION AS OF "
                            f"{snaps_antes[-1].snapshot_id} WHERE id_siniestro = 'SIN-00042'"))[0]
    check(antes["estado"] == "PAGADO" and float(antes["monto_pagado"]) == 17250,
          f"ANTES (time travel): PAGADO 17,250 ({antes})")
    snaps = spark.sql("SELECT snapshot_id FROM lh.silver.siniestros.snapshots").count()
    check(snaps == len(snaps_antes) + 1, f"el UPDATE creo un snapshot nuevo ({len(snaps_antes)} -> {snaps})")
    check(tabla("silver.siniestros").count() == total_antes, "el UPDATE no cambio la cantidad de filas")
    otras = spark.sql("SELECT count(*) FROM lh.silver.siniestros WHERE flag_fraude").first()[0]
    check(otras == 1, "solo SIN-00042 quedo marcado como fraude")

    seccion("Idempotencia: correr de nuevo los labs (como ./lab.sh 2, 3 y 4 otra vez)")
    correr_job("bronze_to_silver.py")
    check("flag_fraude" not in tabla("silver.siniestros").columns, "Lab 2 de nuevo: Silver vuelve al esquema original")
    correr_job("silver_to_gold.py")
    check(tabla("gold.agg_siniestralidad_producto_anual").count() == sp.count(), "Lab 3 de nuevo: mismo Gold")
    correr_job("silver_auditoria.py")
    correr_job("silver_auditoria.py")
    check(spark.sql("SELECT count(*) FROM lh.silver.siniestros WHERE flag_fraude").first()[0] == 1,
          "Lab 4 dos veces seguidas: no se rompe")
else:
    seccion("Lab 4 · omitido en modo simulado (necesita Iceberg real: usa --iceberg)")

spark.stop()
shutil.rmtree(TMP, ignore_errors=True)
print()
if fallan:
    print(f"\033[31mLogica: {fallan} fallaron, {pasan} OK\033[0m")
    sys.exit(1)
print(f"\033[32mLogica ({'Iceberg real' if ICEBERG else 'simulada'}): {pasan} verificaciones OK\033[0m")
