#!/usr/bin/env bash
# Funciones compartidas por deploy.sh, lab.sh y cleanup.sh. No se ejecuta solo.

verde()  { printf '\033[32m%s\033[0m\n' "$*"; }
amarillo() { printf '\033[33m%s\033[0m\n' "$*"; }
rojo()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
paso()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
morir()  { rojo "ERROR: $*"; exit 1; }

verificar_requisitos() {
  command -v aws >/dev/null 2>&1 || morir "No encuentro la AWS CLI. Usa AWS CloudShell o instala la CLI v2."
  command -v python3 >/dev/null 2>&1 || morir "No encuentro python3."
  local version
  version=$(aws --version 2>&1 | sed -E 's#^aws-cli/([0-9]+).*#\1#')
  [ "$version" = "2" ] || morir "Necesitas AWS CLI v2 (tienes: $(aws --version 2>&1))."
  aws s3tables help >/dev/null 2>&1 || morir "Tu AWS CLI es antigua y no conoce 's3tables'. Actualizala o usa AWS CloudShell."
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || morir "No hay credenciales de AWS configuradas (aws configure / aws sso login)."
  export ACCOUNT_ID
  configurar_nombres
}

# Estandar de nombres del proyecto (ver seccion "Nomenclatura" del README):
#   recursos AWS      {proyecto}-{entorno}-{componente}   -> guion medio
#   objetos de datos  {proyecto}_{entorno}_{capa}          -> guion bajo
# shellcheck disable=SC2034  # las variables se usan en los scripts que cargan este archivo
configurar_nombres() {
  PROYECTO="${PROYECTO:-lkh}"
  ENTORNO="${ENTORNO:-lab}"
  echo "$PROYECTO" | grep -Eq '^[a-z0-9]{2,10}$' || morir "--proyecto: 2-10 minusculas o numeros, sin guiones (ej: lkh)"
  echo "$ENTORNO"  | grep -Eq '^[a-z0-9]{2,5}$'  || morir "--entorno: 2-5 minusculas o numeros (ej: lab, dev, qa, prd)"
  BASE="${PROYECTO}-${ENTORNO}"
  STACK="${BASE}-stack"
  DB_BRONZE="${PROYECTO}_${ENTORNO}_bronze"
  # Tags corporativos: se aplican a todo el stack
  OWNER="${OWNER:-$(aws sts get-caller-identity --query Arn --output text 2>/dev/null | sed 's#.*/##')}"
  CENTRO_COSTO="${CENTRO_COSTO:-workshop-awscd}"
}

existe_stack() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" >/dev/null 2>&1
}

existe_bucket() {
  aws s3api head-bucket --region "$REGION" --bucket "$1" >/dev/null 2>&1
}

# Nombres derivados del estandar, sin preguntarle al stack. Se usan cuando la
# infraestructura se creo a mano en la consola (labs/manual-consola) y en
# cleanup.sh cuando alguien ya borro el stack y quedaron recursos huerfanos.
# shellcheck disable=SC2034  # las variables se usan en los scripts que cargan este archivo
nombres_por_convencion() {
  RAW_BUCKET="${BASE}-raw-${ACCOUNT_ID}-${REGION}"
  TABLE_BUCKET="${BASE}-tables"
  WORKGROUP="${BASE}-wg-analistas"
  JOB_SILVER="${BASE}-job-bronze-to-silver"
  JOB_GOLD="${BASE}-job-silver-to-gold"
  JOB_LAB4="${BASE}-job-silver-auditoria"
  ROLE_GLUE="${BASE}-role-glue-${REGION}"
  BUDGET="${BASE}-budget-5usd"
  CATALOGO_TABLES="s3tablescatalog/${TABLE_BUCKET}"
  # El ARN se consulta (no se arma a mano) para no asumir la particion de AWS.
  TABLE_BUCKET_ARN=$(aws s3tables list-table-buckets --region "$REGION" \
    --query "tableBuckets[?name=='$TABLE_BUCKET'].arn | [0]" --output text 2>/dev/null || true)
  [ "$TABLE_BUCKET_ARN" = "None" ] && TABLE_BUCKET_ARN=""
  return 0
}

# resolver_recursos -> deja MODO en:
#   script   la infraestructura la creo CloudFormation (./lab.sh 0 o ./deploy.sh)
#   consola  no hay stack, pero hay recursos con los nombres del estandar:
#            los creaste a mano siguiendo labs/manual-consola
#   ninguno  todavia no hay nada
# y carga los nombres de los recursos desde el origen que corresponda.
# shellcheck disable=SC2034  # MODO se usa en lab.sh, deploy.sh y cleanup.sh
resolver_recursos() {
  if existe_stack; then
    MODO="script"
    cargar_salidas
  else
    nombres_por_convencion
    if existe_bucket "$RAW_BUCKET" || [ -n "$TABLE_BUCKET_ARN" ]; then
      MODO="consola"
    else
      MODO="ninguno"
    fi
  fi
}

# salida_stack <NombreOutput>
salida_stack() {
  aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

# shellcheck disable=SC2034  # las variables se usan en deploy.sh y cleanup.sh
cargar_salidas() {
  RAW_BUCKET=$(salida_stack RawBucket)
  TABLE_BUCKET=$(salida_stack TableBucketName)
  TABLE_BUCKET_ARN=$(salida_stack TableBucketArn)
  JOB_SILVER=$(salida_stack JobSilver)
  JOB_GOLD=$(salida_stack JobGold)
  JOB_LAB4=$(salida_stack JobLab4)
  WORKGROUP=$(salida_stack WorkGroup)
  ROLE_GLUE="${BASE}-role-glue-${REGION}"
  BUDGET="${BASE}-budget-5usd"
  CATALOGO_TABLES="s3tablescatalog/${TABLE_BUCKET}"
}

# athena <sql> [catalogo] [base]   -> deja el id en ULTIMA_CONSULTA
athena() {
  local sql="$1" catalogo="${2:-AwsDataCatalog}" base="${3:-}"
  local contexto="{\"Catalog\":\"$catalogo\"}"
  [ -n "$base" ] && contexto="{\"Catalog\":\"$catalogo\",\"Database\":\"$base\"}"
  ULTIMA_CONSULTA=$(aws athena start-query-execution --region "$REGION" \
    --work-group "$WORKGROUP" \
    --query-execution-context "$contexto" \
    --query-string "$sql" \
    --query QueryExecutionId --output text) || return 1
  local estado
  while :; do
    estado=$(aws athena get-query-execution --region "$REGION" \
      --query-execution-id "$ULTIMA_CONSULTA" --query QueryExecution.Status.State --output text)
    case "$estado" in
      SUCCEEDED) return 0 ;;
      FAILED|CANCELLED)
        rojo "Athena: $(aws athena get-query-execution --region "$REGION" \
          --query-execution-id "$ULTIMA_CONSULTA" \
          --query QueryExecution.Status.StateChangeReason --output text)"
        return 1 ;;
      *) sleep 2 ;;
    esac
  done
}

# athena_tabla <sql> [catalogo] [base] -> ejecuta y muestra el resultado como tabla
athena_tabla() {
  athena "$@" || return 1
  aws athena get-query-results --region "$REGION" --query-execution-id "$ULTIMA_CONSULTA" \
    --max-items 15 --output json | python3 -c '
import json, sys
filas = json.load(sys.stdin)["ResultSet"]["Rows"]
datos = [[c.get("VarCharValue", "") for c in f["Data"]] for f in filas]
if not datos:
    sys.exit(0)
anchos = [max(len(f[i]) for f in datos) for i in range(len(datos[0]))]
for n, f in enumerate(datos):
    print("  " + " | ".join(v.ljust(a) for v, a in zip(f, anchos)))
    if n == 0:
        print("  " + "-+-".join("-" * a for a in anchos))
'
}

# correr_glue <nombre-job>  -> espera hasta que termine
correr_glue() {
  local job="$1" run estado inicio
  run=$(aws glue start-job-run --region "$REGION" --job-name "$job" --query JobRunId --output text) \
    || morir "No pude iniciar el job $job"
  inicio=$(date +%s)
  printf '   job %s (run %s) ' "$job" "$run"
  while :; do
    estado=$(aws glue get-job-run --region "$REGION" --job-name "$job" --run-id "$run" \
      --query JobRun.JobRunState --output text)
    case "$estado" in
      SUCCEEDED) printf ' OK (%ss)\n' "$(( $(date +%s) - inicio ))"; return 0 ;;
      FAILED|ERROR|TIMEOUT|STOPPED)
        printf '\n'
        rojo "El job $job termino en $estado:"
        aws glue get-job-run --region "$REGION" --job-name "$job" --run-id "$run" \
          --query JobRun.ErrorMessage --output text >&2
        rojo "Revisa los logs en CloudWatch: /aws-glue/jobs/error y /aws-glue/jobs/output (run $run)"
        return 1 ;;
      *) printf '.'; sleep 15 ;;
    esac
  done
}
