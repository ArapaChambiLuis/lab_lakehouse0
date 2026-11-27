#!/usr/bin/env python3
"""
Pruebas de CONSISTENCIA: que el manual por consola, la plantilla de
CloudFormation, los scripts de shell y los jobs de Glue digan lo mismo.

Es lo que garantiza que alguien que sigue la demo en la consola y alguien que
corre ./lab.sh terminen con los MISMOS recursos, y que el script pueda tomar
la posta de lo que se hizo a mano.

Uso:  python3 tests/test_consistencia.py
"""
import ast
import filecmp
import json
import os
import re
import subprocess
import sys
import tempfile

import yaml

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANUAL = os.path.join(RAIZ, "labs", "manual-consola", "README.md")
CTX = {"Proyecto": "lkh", "Entorno": "lab", "AWS::AccountId": "<CUENTA>", "AWS::Region": "us-east-1"}

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
    print(f"\n\033[1m▶ {t}\033[0m")


def leer(*ruta):
    with open(os.path.join(RAIZ, *ruta), encoding="utf-8") as f:
        return f.read()


# ---------- plantilla: YAML con las etiquetas de CloudFormation ----------
class Tag:
    def __init__(self, tag, val):
        self.tag, self.val = tag, val


class CfnLoader(yaml.SafeLoader):
    pass


def _tag(loader, suffix, node):
    if isinstance(node, yaml.ScalarNode):
        return Tag(suffix, loader.construct_scalar(node))
    if isinstance(node, yaml.SequenceNode):
        return Tag(suffix, loader.construct_sequence(node, deep=True))
    return Tag(suffix, loader.construct_mapping(node, deep=True))


CfnLoader.add_multi_constructor("!", _tag)
T = yaml.load(leer("infra", "template.yaml"), Loader=CfnLoader)
R = T["Resources"]


def render(v):
    """Resuelve !Sub / !Ref con lkh, lab, <CUENTA> y us-east-1."""
    if isinstance(v, Tag) and v.tag == "Sub":
        s = v.val if isinstance(v.val, str) else v.val[0]

        def rep(m):
            k = m.group(1)
            if k in CTX:
                return CTX[k]
            if k == "RawBucket":
                return render(R["RawBucket"]["Properties"]["BucketName"])
            if k in ("TableBucket.TableBucketARN",):
                return "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/" + render(R["TableBucket"]["Properties"]["TableBucketName"])
            if k == "RawBucket.Arn":
                return "arn:aws:s3:::" + render(R["RawBucket"]["Properties"]["BucketName"])
            return m.group(0)
        return re.sub(r"\$\{([^}]+)\}", rep, s)
    if isinstance(v, Tag) and v.tag == "Ref":
        if v.val in CTX:
            return CTX[v.val]
        if v.val == "RawBucket":
            return render(R["RawBucket"]["Properties"]["BucketName"])
        return v.val
    if isinstance(v, Tag) and v.tag == "GetAtt":
        n = v.val if isinstance(v.val, str) else ".".join(v.val)
        if n == "TableBucket.TableBucketARN":
            return "arn:aws:s3tables:us-east-1:<CUENTA>:bucket/" + render(R["TableBucket"]["Properties"]["TableBucketName"])
        if n == "RawBucket.Arn":
            return "arn:aws:s3:::" + render(R["RawBucket"]["Properties"]["BucketName"])
        return n
    return v


man = leer("labs", "manual-consola", "README.md")
comun = leer("scripts", "comun.sh")
etapas = leer("scripts", "etapas.sh")
simulado = leer("tests", "aws_simulado", "aws")

# ------------------------------------------------------------------
seccion("Nombres: plantilla = scripts (modo consola) = manual")
nombres_tpl = {
    "RAW_BUCKET": render(R["RawBucket"]["Properties"]["BucketName"]),
    "TABLE_BUCKET": render(R["TableBucket"]["Properties"]["TableBucketName"]),
    "WORKGROUP": render(R["AthenaWorkGroup"]["Properties"]["Name"]),
    "ROLE_GLUE": render(R["GlueRole"]["Properties"]["RoleName"]),
    "BUDGET": render(R["Presupuesto"]["Properties"]["Budget"]["BudgetName"]),
    "JOB_SILVER": render(R["JobBronzeToSilver"]["Properties"]["Name"]),
    "JOB_GOLD": render(R["JobSilverToGold"]["Properties"]["Name"]),
    "JOB_LAB4": render(R["JobSilverAuditoria"]["Properties"]["Name"]),
}
# Las salidas del stack apuntan a los mismos jobs que los nombres por convencion
salidas = {k: v["Value"].val for k, v in T["Outputs"].items() if isinstance(v["Value"], Tag)}
check(salidas.get("JobSilver") == "JobBronzeToSilver" and salidas.get("JobGold") == "JobSilverToGold"
      and salidas.get("JobLab4") == "JobSilverAuditoria",
      "las salidas JobSilver/JobGold/JobLab4 del stack apuntan a los jobs correctos")

conv = dict(re.findall(r'^\s+(\w+)="\$\{BASE\}([^"]*)"', comun, re.M))
for var, nombre in nombres_tpl.items():
    sufijo = conv.get(var)
    nombre_sh = None if sufijo is None else (
        "lkh-lab" + sufijo.replace("${ACCOUNT_ID}", "<CUENTA>").replace("${REGION}", "us-east-1"))
    check(nombre_sh == nombre, f"{var}: comun.sh ({nombre_sh}) = plantilla ({nombre})")
    check(nombre in man, f"el manual usa el nombre {nombre}")
check("lkh_lab_bronze" in man and 'DB_BRONZE="${PROYECTO}_${ENTORNO}_bronze"' in comun,
      "base de Bronze lkh_lab_bronze: igual en manual y scripts")

# ------------------------------------------------------------------
seccion("Jobs de Glue: plantilla = scripts .py = manual = chequeo de consola")
mapa_etapas = dict(re.findall(r'"\$(JOB_\w+)"\)\s+(?:\[[^\]]+\] \|\| continue; )?archivo="([\w.]+)"', etapas))
for logico, var in (("JobBronzeToSilver", "JOB_SILVER"), ("JobSilverToGold", "JOB_GOLD"),
                    ("JobSilverAuditoria", "JOB_LAB4")):
    p = R[logico]["Properties"]
    nombre = render(p["Name"])
    script = render(p["Command"]["ScriptLocation"]).rsplit("/", 1)[-1]
    args = p["DefaultArguments"]
    check(os.path.exists(os.path.join(RAIZ, "glue", script)), f"{nombre}: existe glue/{script}")
    check(mapa_etapas.get(var) == script, f"{nombre}: revisar_infra_consola espera {script}",
          f"etapas.sh dice {mapa_etapas.get(var)}")
    fuente = leer("glue", script)
    m = re.search(r"getResolvedOptions\(sys\.argv,\s*\[([^\]]*)\]\)", fuente)
    leidos = set(re.findall(r'"(\w+)"', m.group(1))) if m else set()
    definidos = {k[2:] for k in args if k != "--datalake-formats"}
    check(leidos == definidos, f"{nombre}: los parametros del job = los que lee el script",
          f"plantilla {sorted(definidos)} vs script {sorted(leidos)}")
    for k in args:
        check(f"`{k}`" in man, f"{nombre}: el manual pide el parametro {k}")
    check(script in man, f"el manual sube y usa {script}")
    check(str(p["GlueVersion"]) == "5.0" and "Glue 5.0" in man, f"{nombre}: Glue 5.0 en plantilla y manual")
    check(p["WorkerType"] == "G.1X" and "G.1X" in man, f"{nombre}: worker G.1X en plantilla y manual")
    check(p["NumberOfWorkers"] == 2 and p["Timeout"] == 20 and p["MaxRetries"] == 0,
          f"{nombre}: 2 workers, timeout 20, 0 reintentos (como el manual)")
check("| **Requested number of workers** | `2` |" in man and "| **Job timeout (minutes)** | `20` |" in man
      and "| **Number of retries** | `0` |" in man, "el manual pide 2 workers, timeout 20 y 0 reintentos")

# ------------------------------------------------------------------
seccion("Politica IAM: la del manual = la de la plantilla")
bloque = re.search(r"```json\n(.*?)```", man, re.S)
pol_man = json.loads(bloque.group(1)) if bloque else {"Statement": []}
pol_tpl = R["GlueRole"]["Properties"]["Policies"][0]["PolicyDocument"]["Statement"]
por_sid_man = {s["Sid"]: s for s in pol_man["Statement"]}
for st in pol_tpl:
    sm = por_sid_man.get(st["Sid"], {})
    acc = lambda a: sorted(a if isinstance(a, list) else [a])  # noqa: E731
    check(acc(sm.get("Action", [])) == acc(st["Action"]), f"{st['Sid']}: mismas acciones")
    check(sorted(sm.get("Resource", [])) == sorted(render(r) for r in st["Resource"]),
          f"{st['Sid']}: mismos recursos", f"manual {sm.get('Resource')}")
adj = R["GlueRole"]["Properties"]["ManagedPolicyArns"][0].rsplit("/", 1)[-1]
check(adj in man, f"el manual adjunta {adj}")

# ------------------------------------------------------------------
seccion("Bucket y Athena: mismas reglas en plantilla y manual")
reglas = R["RawBucket"]["Properties"]["LifecycleConfiguration"]["Rules"]
for r in reglas:
    check(r["Id"] in man, f"regla de ciclo de vida {r['Id']} en el manual")
dias = {r["Id"]: r.get("ExpirationInDays") or r["AbortIncompleteMultipartUpload"]["DaysAfterInitiation"] for r in reglas}
check(dias == {"limpiar-resultados-athena": 7, "abortar-multipart-incompletos": 1}
      and "`7` días" in man and "`1` día" in man, "7 dias (resultados) y 1 dia (multipart) en ambos")
corte = R["AthenaWorkGroup"]["Properties"]["WorkGroupConfiguration"]["BytesScannedCutoffPerQuery"]
check(corte == 1024 ** 3 and "**Data limits:** `1` **GB**" in man, "tope de Athena de 1 GB en ambos")
check("athena-results/" in render(R["AthenaWorkGroup"]["Properties"]["WorkGroupConfiguration"]
                                    ["ResultConfiguration"]["OutputLocation"]) and "athena-results/" in man,
      "resultados de Athena en athena-results/ en ambos")
tags_stack = set(re.findall(r'"(\w+)=', etapas.split("--tags", 1)[1].split("\n\n", 1)[0]))
check(tags_stack == {"Proyecto", "Entorno", "Owner", "CentroCosto"}
      and all(f"`{t}`" in man for t in tags_stack), "los 4 tags del stack estan en el manual")

# ------------------------------------------------------------------
seccion("Tablas: jobs = scripts = manual = pruebas")
silver = re.findall(r'escribir\(\w+, "(\w+)"', leer("glue", "bronze_to_silver.py"))
gold = re.findall(r'"(agg_\w+)": f"""', leer("glue", "silver_to_gold.py"))
check(len(silver) == 4 and len(gold) == 3, f"silver {silver} / gold {gold}")
limpieza = man.split("## 11.", 1)[1]
for t in silver + gold:
    check(t in limpieza, f"la limpieza del manual borra {t}")
check(set(silver) == set(re.search(r"SILVER = (\[[^\]]*\])", simulado).group(1).strip("[]").replace('"', "").replace(" ", "").split(","))
      and set(gold) == set(re.findall(r'"(agg_\w+)"', re.search(r"GOLD = \[[^\]]*\]", simulado).group(0))),
      "la AWS simulada de las pruebas conoce las mismas tablas")
for t in re.findall(r"existe_tabla (?:gold|silver) (\w+)", leer("lab.sh") + etapas):
    check(t in silver + gold, f"lab.sh/etapas.sh revisan una tabla que existe: {t}")

tablas_ddl = re.findall(r"__DB_BRONZE__\.(\w+)", leer("sql", "bronze_ddl.sql"))
tablas_gen = re.findall(r'"(\w+)": (?:clientes|polizas|pagos|siniestros),', leer("data", "generator.py"))
tablas_etapa = re.search(r"for tabla in ([\w ]+); do", etapas).group(1).split()
check(sorted(tablas_ddl) == sorted(tablas_gen) == sorted(tablas_etapa),
      f"Bronze: DDL = generador = etapa_bronze ({sorted(tablas_ddl)})")
for t in tablas_ddl:
    check(f"`bronze/{t}/`" in man, f"el manual crea la carpeta bronze/{t}/")

# ------------------------------------------------------------------
seccion("Guia de la demo por lab: lo que nombra existe")
guia = leer("labs", "guia-demo-por-lab.md")
for var in ("JOB_SILVER", "JOB_GOLD", "JOB_LAB4", "TABLE_BUCKET", "WORKGROUP", "ROLE_GLUE", "BUDGET"):
    check(nombres_tpl[var] in guia, f"la guia usa el nombre {nombres_tpl[var]}")
for n in range(5):
    check(f"./lab.sh {n}" in guia, f"la guia indica el rescate ./lab.sh {n}")
for t in gold:
    check(t in guia or t.replace("agg_", "") not in guia, f"la guia nombra bien la tabla gold {t}")
check("__DB_BRONZE__" in leer("sql", "bronze_ddl.sql") and "__RAW_BUCKET__" in leer("sql", "bronze_ddl.sql"),
      "el kit de la guia reemplaza placeholders que existen en sql/bronze_ddl.sql")
for parte in re.findall(r"manual-consola/README\.md#(\d+)-", guia):
    check(re.search(rf"^## {parte}\. ", man, re.M) is not None, f"la guia enlaza a la parte {parte} del manual, que existe")

# ------------------------------------------------------------------
seccion("Reglas de S3 Tables en los jobs")
def ctas_en(fuente):
    """Busca en el CODIGO (no en comentarios ni docstrings) lo que S3 Tables rechaza."""
    malos = []
    for nodo in ast.walk(ast.parse(fuente)):
        if not isinstance(nodo, ast.Call):
            continue
        if isinstance(nodo.func, ast.Attribute) and nodo.func.attr in ("create", "createOrReplace"):
            malos.append(f".{nodo.func.attr}() en la linea {nodo.lineno}")
        if isinstance(nodo.func, ast.Attribute) and nodo.func.attr == "sql" and nodo.args:
            arg = nodo.args[0]
            partes = [v.value for v in ast.walk(arg) if isinstance(v, ast.Constant) and isinstance(v.value, str)]
            texto = " ".join(" ".join(partes).split())
            if re.search(r"CREATE OR REPLACE TABLE|CREATE TABLE.*\bAS\s+SELECT|REPLACE TABLE .* AS", texto, re.I):
                malos.append(f"CTAS en spark.sql de la linea {nodo.lineno}")
    return malos


for f in sorted(os.listdir(os.path.join(RAIZ, "glue"))):
    if f.endswith(".py"):
        malos = ctas_en(leer("glue", f))
        check(not malos, f"{f}: sin CTAS (S3 Tables no soporta staged create)", f"encontrado: {malos}")

# ------------------------------------------------------------------
seccion("Datos: los CSV del repo = los que genera el script")
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable, os.path.join(RAIZ, "data", "generator.py"), "--out", tmp],
                   check=True, capture_output=True)
    for t in tablas_ddl:
        commit = os.path.join(RAIZ, "data", "sample", f"{t}.csv")
        check(os.path.exists(commit) and filecmp.cmp(commit, os.path.join(tmp, f"{t}.csv"), shallow=False),
              f"data/sample/{t}.csv es identico a lo que genera generator.py",
              "si no, la ruta consola (CSV del repo) y la ruta script (CSV generado) tendrian datos distintos")

# ------------------------------------------------------------------
seccion("Repo: permisos de ejecucion, enlaces y nombres viejos")
modos = subprocess.run(["git", "ls-files", "-s"], cwd=RAIZ, capture_output=True, text=True).stdout
for linea in modos.splitlines():
    modo, _, _, ruta = linea.split(None, 3)
    if ruta.endswith(".sh") or ruta == "tests/aws_simulado/aws":
        check(modo == "100755", f"{ruta} es ejecutable en git", "arreglo: git update-index --chmod=+x " + ruta)

for base, _, archivos in os.walk(RAIZ):
    if "/.git" in base:
        continue
    for a in archivos:
        if not a.endswith(".md"):
            continue
        ruta = os.path.join(base, a)
        texto = open(ruta, encoding="utf-8").read()
        for destino in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", texto):
            if destino.startswith(("http://", "https://", "mailto:")):
                continue
            check(os.path.exists(os.path.normpath(os.path.join(base, destino))),
                  f"{os.path.relpath(ruta, RAIZ)}: enlace a {destino} existe")

viejos = [r"lakehouse-aseg-", r"aseguradora_bronze", r"lab4_auditoria", r"glue/silver\.py", r"glue/gold\.py",
          r"\bsiniestralidad_producto\b(?!_)", r"--prefijo"]
for base, _, archivos in os.walk(RAIZ):
    if "/.git" in base or "/tests" in base:
        continue
    for a in archivos:
        if a.endswith((".md", ".sh", ".py", ".sql", ".yaml")):
            ruta = os.path.join(base, a)
            texto = open(ruta, encoding="utf-8").read()
            hall = [v for v in viejos if re.search(v, texto)]
            check(not hall, f"{os.path.relpath(ruta, RAIZ)}: sin nombres del estandar viejo", f"{hall}")

print()
if fallan:
    print(f"\033[31mConsistencia: {fallan} fallaron, {pasan} OK\033[0m")
    sys.exit(1)
print(f"\033[32mConsistencia: {pasan} verificaciones OK\033[0m")
