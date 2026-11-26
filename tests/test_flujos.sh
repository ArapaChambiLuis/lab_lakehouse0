#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Pruebas de FLUJO: deploy.sh, lab.sh y cleanup.sh contra una AWS CLI
#  simulada con estado (tests/aws_simulado/aws). Sin cuenta de AWS.
#
#  Cubre las dos rutas del workshop y su mezcla:
#    - ruta script:  todo con ./lab.sh / ./deploy.sh
#    - ruta consola: infraestructura creada a mano (labs/manual-consola)
#    - rescate:      alguien que va en consola se pierde y alcanza con scripts
#
#  Uso:  tests/test_flujos.sh
# ------------------------------------------------------------------
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SIM="$RAIZ/tests/aws_simulado"
TMP="$(mktemp -d)"
export AWS_SIMULADO_DIR="$TMP/estado"
export PATH="$SIM:$PATH"
export LAKEHOUSE_PAUSA_LAB4=0
export NO_COLOR=1

PASAN=0
FALLAN=0
SALIDA=""
CODIGO=0

escenario() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; rm -rf "$AWS_SIMULADO_DIR"; mkdir -p "$AWS_SIMULADO_DIR"; }
correr()    { SALIDA=$("$@" 2>&1 </dev/null); CODIGO=$?; }
ok()        { PASAN=$((PASAN + 1)); printf '   \033[32m✔\033[0m %s\n' "$1"; }
mal()       { FALLAN=$((FALLAN + 1)); printf '   \033[31m✘ %s\033[0m\n' "$1"; printf '%s\n' "$SALIDA" | tail -15 | sed 's/^/     | /'; }
codigo()    { if [ "$CODIGO" -eq "$1" ]; then ok "${2:-termina con codigo $1}"; else mal "${2:-codigo $1} (fue $CODIGO)"; fi; }
dice()      { if printf '%s' "$SALIDA" | grep -qF -- "$1"; then ok "dice: $1"; else mal "deberia decir: $1"; fi; }
no_dice()   { if printf '%s' "$SALIDA" | grep -qF -- "$1"; then mal "no deberia decir: $1"; else ok "no dice: $1"; fi; }
llamo()     { if grep -qE -- "$1" "$AWS_SIMULADO_DIR/llamadas.log"; then ok "${2:-llamo a: $1}"; else mal "${2:-deberia llamar a: $1}"; fi; }
no_llamo()  { if grep -qE -- "$1" "$AWS_SIMULADO_DIR/llamadas.log" 2>/dev/null; then mal "${2:-no deberia llamar a: $1}"; else ok "${2:-no llamo a: $1}"; fi; }
estado()    { python3 -c "import json,sys; e=json.load(open('$AWS_SIMULADO_DIR/estado.json')); print($1)"; }
igual()     { local v; v=$(estado "$1"); if [ "$v" = "$2" ]; then ok "${3:-$1 = $2}"; else mal "${3:-$1} deberia ser $2 (es $v)"; fi; }
sembrar()   { aws __sembrar "$@"; }

cd "$RAIZ" || exit 1

# ------------------------------------------------------------------
escenario "Ruta script: ./deploy.sh despliega todo de punta a punta"
correr ./deploy.sh --email luis@correo.com
codigo 0
llamo "cloudformation deploy" "lanza CloudFormation"
llamo "start-job-run .*--job-name lkh-lab-job-bronze-to-silver"
llamo "start-job-run .*--job-name lkh-lab-job-silver-to-gold"
llamo "start-job-run .*--job-name lkh-lab-job-silver-auditoria"
igual "len(e['tablebuckets']['lkh-lab-tables']['ns']['gold'])" "3" "gold queda con sus 3 tablas"
igual "e['lab4']" "True" "el Lab 4 quedo aplicado"
igual "'lkh-lab-budget-5usd' in e['budgets']" "True" "crea el presupuesto si hay email"

# ------------------------------------------------------------------
escenario "Ruta script: ./lab.sh 0 a 4, uno por uno"
for n in 0 1 2 3 4; do
  correr ./lab.sh "$n"
  codigo 0 "./lab.sh $n termina bien"
done
correr ./lab.sh estado
dice "Origen: CloudFormation"
dice "Siguiente paso: labs/lab5-gobierno"

# ------------------------------------------------------------------
escenario "Prerequisitos: ./lab.sh 3 sin haber hecho el Lab 2"
correr ./lab.sh 0; correr ./lab.sh 1
correr ./lab.sh 3
codigo 1
dice "Antes necesitas el Lab 2"
dice "./deploy.sh --hasta silver"
no_llamo "start-job-run .*--job-name lkh-lab-job-silver-to-gold" "no corre Gold sin Silver"

# ------------------------------------------------------------------
escenario "Sin nada creado: ./lab.sh 1 pide el Lab 0"
correr ./lab.sh 1
codigo 1
dice "Antes necesitas el Lab 0"

# ------------------------------------------------------------------
escenario "Ruta consola: infraestructura hecha a mano, labs con ./lab.sh"
sembrar consola
correr ./lab.sh estado
dice "Origen: creado a mano en la consola"
dice "Siguiente paso: ./lab.sh 1"
for n in 1 2 3 4; do
  correr ./lab.sh "$n"
  codigo 0 "./lab.sh $n funciona sobre la infraestructura de la consola"
done
no_llamo "cloudformation deploy" "nunca lanza CloudFormation encima de lo hecho a mano"
igual "e['lab4']" "True" "llega hasta el Lab 4"

# ------------------------------------------------------------------
escenario "Ruta consola: namespaces olvidados se crean solos"
sembrar consola sin_namespaces
correr ./lab.sh 1; correr ./lab.sh 2
codigo 0
dice "namespace silver: no existia, lo cree"
igual "sorted(e['tablebuckets']['lkh-lab-tables']['ns'])" "['gold', 'silver']"

# ------------------------------------------------------------------
escenario "Ruta consola: job mal configurado (ARN equivocado) se detecta antes de correr"
sembrar consola job_arn_malo
correr ./lab.sh 1
codigo 0 "el Lab 1 no necesita los jobs: funciona"
correr ./lab.sh 2
codigo 1
dice "--TABLE_BUCKET_ARN debe ser arn:aws:s3tables:us-east-1:111122223333:bucket/lkh-lab-tables"
dice "paso 5.1"
dice "./lab.sh 0 --reiniciar"
no_llamo "start-job-run" "no lanza un job que va a fallar"

# ------------------------------------------------------------------
escenario "Ruta consola: falta el parametro --datalake-formats"
sembrar consola job_sin_formato
correr ./lab.sh 1; correr ./lab.sh 2
codigo 1
dice "falta el parametro --datalake-formats = iceberg"

# ------------------------------------------------------------------
escenario "Ruta consola incompleta: sin rol IAM"
sembrar consola sin_rol
correr ./lab.sh 1
codigo 0 "el Lab 1 funciona sin el rol"
correr ./lab.sh 2
codigo 1
dice "Rol IAM lkh-lab-role-glue-us-east-1  (manual: paso 4)"

# ------------------------------------------------------------------
escenario "Rescate: alguien en consola se pierde y alcanza con ./deploy.sh --hasta gold"
sembrar consola
correr ./deploy.sh --hasta gold
codigo 0
no_llamo "cloudformation deploy" "usa lo de la consola, sin CloudFormation"
llamo "start-job-run .*--job-name lkh-lab-job-silver-to-gold"
no_llamo "start-job-run .*--job-name lkh-lab-job-silver-auditoria" "se detiene en gold"
correr ./lab.sh 4
codigo 0 "y sigue con el grupo en el Lab 4"

# ------------------------------------------------------------------
escenario "Rescate: perdido a mitad de la infraestructura en consola"
sembrar consola_parcial
correr ./lab.sh 0
codigo 1 "no lanza CloudFormation encima (chocaria con lo creado a mano)"
dice "./lab.sh 0 --reiniciar"
no_llamo "cloudformation deploy"
correr ./lab.sh 0 --reiniciar
codigo 0 "con --reiniciar limpia y despliega por script"
llamo "cloudformation deploy"
correr ./lab.sh estado
dice "Origen: CloudFormation"

# ------------------------------------------------------------------
escenario "Rescate: ./deploy.sh con infraestructura de consola incompleta"
sembrar consola sin_jobs
correr ./deploy.sh --hasta silver
codigo 1
dice "Job de Glue lkh-lab-job-bronze-to-silver  (manual: paso 5)"
dice "./deploy.sh --reiniciar --hasta silver"
correr ./deploy.sh --reiniciar --hasta silver
codigo 0
llamo "cloudformation deploy"

# ------------------------------------------------------------------
escenario "Limpieza con stack: deja la cuenta vacia"
correr ./deploy.sh
correr ./cleanup.sh --si
codigo 0
igual "e['stack']" "None" "el stack se borra (las tablas se borraron antes)"
igual "len(e['buckets']) + len(e['tablebuckets']) + len(e['jobs']) + len(e['roles']) + len(e['workgroups'])" "0" "no queda ningun recurso"

# ------------------------------------------------------------------
escenario "Limpieza de lo creado a mano en la consola (modo huerfanos)"
sembrar consola
correr ./lab.sh 1; correr ./lab.sh 2; correr ./lab.sh 3
correr ./cleanup.sh --si
codigo 0
dice "Modo huerfanos"
igual "len(e['buckets']) + len(e['tablebuckets']) + len(e['jobs']) + len(e['roles']) + len(e['workgroups']) + len(e['budgets'])" "0" "borra bucket, table bucket, jobs, rol, workgroup y presupuesto"
igual "list(e['bases'])" "[]" "borra la base de Bronze"

# ------------------------------------------------------------------
escenario "Validacion de argumentos"
correr ./lab.sh 1 --entorno DEV-1
codigo 1
dice "--entorno: 2-5 minusculas"
correr ./lab.sh 7
codigo 1
dice "Argumento no valido"
correr ./deploy.sh --hasta plata
codigo 1
dice "--hasta debe ser"

# ------------------------------------------------------------------
rm -rf "$TMP"
echo
if [ "$FALLAN" -eq 0 ]; then
  printf '\033[32mFlujos: %s verificaciones OK\033[0m\n' "$PASAN"
else
  printf '\033[31mFlujos: %s fallaron, %s OK\033[0m\n' "$FALLAN" "$PASAN"
  exit 1
fi
