#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Verifica TODO el repo del workshop, sin cuenta de AWS, en 5 capas:
#
#    1. Sintaxis      bash -n + shellcheck en los .sh, compilacion de los .py
#    2. Plantilla     cfn-lint sobre infra/template.yaml
#    3. Consistencia  manual por consola = plantilla = scripts = jobs
#    4. Flujos        deploy.sh / lab.sh / cleanup.sh contra una AWS simulada:
#                     ruta script, ruta consola y rescates entre ambas
#    5. Logica        los jobs de Glue corriendo en PySpark sobre los CSV
#
#  Uso:
#     tests/verificar.sh             logica simulada (sin descargar nada)
#     tests/verificar.sh --iceberg   logica con Iceberg real, incluido el Lab 4
#                                    (descarga iceberg-spark-runtime de Maven)
#     tests/verificar.sh --rapido    sin la capa 5 (no necesita Java ni PySpark)
#
#  Requisitos:  pip install cfn-lint shellcheck-py pyyaml pyspark==3.5.4
#               y Java 17 para la capa 5.
#  Lo mismo corre en GitHub Actions en cada push (.github/workflows/verificacion.yml).
# ------------------------------------------------------------------
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ" || exit 1

LOGICA="simulada"
for a in "$@"; do
  case "$a" in
    --iceberg) LOGICA="iceberg" ;;
    --rapido)  LOGICA="no" ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Opcion desconocida: $a"; exit 2 ;;
  esac
done

RESUMEN=""
FALLAS=0
capa() {  # capa <titulo> <comando...>
  local titulo="$1"; shift
  printf '\n\033[1;36m==================== %s ====================\033[0m\n' "$titulo"
  if "$@"; then
    RESUMEN="${RESUMEN}
  ✔ $titulo"
  else
    RESUMEN="${RESUMEN}
  ✘ $titulo"
    FALLAS=$((FALLAS + 1))
  fi
}
requiere() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "Falta '$1'. Instala:  pip install cfn-lint shellcheck-py pyyaml pyspark==3.5.4"
  return 1
}

SH=(deploy.sh lab.sh cleanup.sh scripts/comun.sh scripts/etapas.sh tests/verificar.sh tests/test_flujos.sh)
PY=(glue/*.py data/generator.py tests/*.py tests/aws_simulado/aws)

sintaxis() {
  local f ok=0
  for f in "${SH[@]}"; do bash -n "$f" || ok=1; done
  requiere shellcheck && shellcheck -x "${SH[@]}" || ok=1
  python3 - "${PY[@]}" <<'PY' || ok=1
import ast, sys
for f in sys.argv[1:]:
    ast.parse(open(f, encoding="utf-8").read(), f)
PY
  [ "$ok" -eq 0 ] && echo "   bash, shellcheck y Python: sin errores"
  return "$ok"
}

plantilla() {
  requiere cfn-lint && cfn-lint infra/template.yaml && echo "   cfn-lint: sin errores"
}

logica() {
  if [ "$LOGICA" = "iceberg" ]; then python3 tests/test_logica.py --iceberg; else python3 tests/test_logica.py; fi
}

capa "1/5 Sintaxis" sintaxis
capa "2/5 Plantilla CloudFormation" plantilla
capa "3/5 Consistencia manual-consola / plantilla / scripts" python3 tests/test_consistencia.py
capa "4/5 Flujos (ruta script, ruta consola y rescates)" tests/test_flujos.sh
if [ "$LOGICA" != "no" ]; then
  capa "5/5 Logica de los jobs de Glue ($LOGICA)" logica
else
  RESUMEN="${RESUMEN}
  · 5/5 Logica: omitida (--rapido)"
fi

printf '\n\033[1mResumen:\033[0m%s\n' "$RESUMEN"
if [ "$FALLAS" -gt 0 ]; then
  printf '\033[31m%s capa(s) con errores\033[0m\n' "$FALLAS"
  exit 1
fi
printf '\033[32mTodo OK\033[0m\n'
