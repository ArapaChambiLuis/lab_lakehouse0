#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Borra todo lo que creo deploy.sh para dejar la cuenta sin costo.
#
#     ./cleanup.sh             (pide confirmacion)
#     ./cleanup.sh --si        (sin preguntar)
#     ./cleanup.sh --region us-east-1 --proyecto lkh --entorno lab
#
#  Tambien funciona si el stack ya no existe (por ejemplo, lo borraste desde
#  la consola): deduce los nombres del estandar y limpia lo que quedo suelto.
#
#  Lo unico que NO borra es el catalogo 's3tablescatalog' de Glue: es
#  compartido por toda la cuenta y region, no cobra, y lo usan otros table
#  buckets. Si de verdad lo quieres fuera:
#     aws glue delete-catalog --catalog-id s3tablescatalog
# ------------------------------------------------------------------
set -euo pipefail
export AWS_PAGER=""

RAIZ="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/comun.sh
source "$RAIZ/scripts/comun.sh"

REGION="${AWS_REGION:-us-east-1}"
CONFIRMADO="no"
RETENCION_DIAS=7

while [ $# -gt 0 ]; do
  case "$1" in
    --region)  REGION="$2"; shift 2 ;;
    --proyecto) PROYECTO="$2"; shift 2 ;;
    --entorno) ENTORNO="$2"; shift 2 ;;
    --si|-y)   CONFIRMADO="si"; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) morir "Opcion desconocida: $1" ;;
  esac
done

# Una subida multiparte a medias no es un objeto: "aws s3 rm" no la ve, pero
# impide borrar el bucket y deja el stack en DELETE_FAILED.
abortar_multipart() {
  local bucket="$1" pendientes clave id
  pendientes=$(aws s3api list-multipart-uploads --region "$REGION" --bucket "$bucket" \
    --query 'Uploads[].[Key,UploadId]' --output text 2>/dev/null || true)
  while read -r clave id; do
    [ -n "${id:-}" ] || continue
    aws s3api abort-multipart-upload --region "$REGION" --bucket "$bucket" \
      --key "$clave" --upload-id "$id" 2>/dev/null \
      && echo "   abortada la subida multiparte de $clave"
  done <<EOF
$pendientes
EOF
}

verificar_requisitos

if existe_stack; then
  HAY_STACK="si"
  cargar_salidas
else
  HAY_STACK="no"
  nombres_por_convencion
  amarillo "No existe el stack $STACK en $REGION."
  echo "   Modo huerfanos: busco por nomenclatura lo que haya quedado suelto."
fi

if [ "$CONFIRMADO" != "si" ]; then
  amarillo "En la region $REGION se va a borrar:"
  if [ "$HAY_STACK" = "si" ]; then
    echo "   - el stack $STACK (bucket, table bucket, 3 jobs de Glue, rol IAM, workgroup)"
  else
    echo "   - lo creado a mano con el estandar ${BASE}-*: jobs, workgroup, rol IAM y presupuesto"
  fi
  [ -n "$RAW_BUCKET" ] && echo "   - el bucket $RAW_BUCKET con todo su contenido"
  [ -n "$TABLE_BUCKET_ARN" ] && echo "   - todas las tablas Iceberg de $TABLE_BUCKET"
  echo "   - la base $DB_BRONZE del Glue Data Catalog"
  printf 'Escribe "borrar" para continuar: '
  read -r respuesta
  [ "$respuesta" = "borrar" ] || { echo "Cancelado."; exit 0; }
fi

paso "1/5 Borrando tablas Iceberg de S3 Tables (silver y gold)"
if [ -n "$TABLE_BUCKET_ARN" ]; then
  for ns in silver gold; do
    tablas=$(aws s3tables list-tables --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
      --namespace "$ns" --query 'tables[].name' --output text 2>/dev/null || true)
    for t in $tablas; do
      [ "$t" = "None" ] && continue
      aws s3tables delete-table --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
        --namespace "$ns" --name "$t"
      echo "   borrada $ns.$t"
    done
  done
else
  echo "   (no existe el table bucket $TABLE_BUCKET)"
fi

paso "2/5 Borrando la base Bronze del Glue Data Catalog"
if aws glue delete-database --region "$REGION" --name "$DB_BRONZE" 2>/dev/null; then
  echo "   borrada $DB_BRONZE"
else
  echo "   (no existia)"
fi

paso "3/5 Vaciando el bucket $RAW_BUCKET"
if [ -n "$RAW_BUCKET" ] && existe_bucket "$RAW_BUCKET"; then
  aws s3 rm "s3://$RAW_BUCKET" --recursive --only-show-errors || true
  abortar_multipart "$RAW_BUCKET"
  echo "   vaciado"
else
  echo "   (no existe)"
fi

paso "4/5 Poniendo retencion de $RETENCION_DIAS dias a los logs de Glue"
# Los /aws-glue/jobs/* son log groups COMPARTIDOS por toda la cuenta y region:
# por eso no se borran. Solo se les pone expiracion si no tenian ninguna, que es
# lo unico del lab que seguiria costando centavos para siempre.
grupos=$(aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix /aws-glue/jobs \
  --query 'logGroups[].[logGroupName,retentionInDays]' --output text 2>/dev/null || true)
if [ -z "$grupos" ]; then
  echo "   (no hay log groups de Glue en $REGION)"
else
  while read -r grupo retencion; do
    [ -n "${grupo:-}" ] || continue
    if [ "${retencion:-None}" = "None" ]; then
      if aws logs put-retention-policy --region "$REGION" --log-group-name "$grupo" \
           --retention-in-days "$RETENCION_DIAS" 2>/dev/null; then
        echo "   $grupo -> expira a los $RETENCION_DIAS dias"
      else
        amarillo "   $grupo: no pude cambiar la retencion (revisa permisos de logs)"
      fi
    else
      echo "   $grupo ya expiraba a los $retencion dias (no lo toco)"
    fi
  done <<EOF
$grupos
EOF
fi

if [ "$HAY_STACK" = "si" ]; then
  paso "5/5 Eliminando el stack $STACK (1-3 min)"
  aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK"
  aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK"
  echo "   stack $STACK eliminado"
else
  paso "5/5 Borrando los recursos huerfanos (sin stack que los elimine)"
  if [ -n "$RAW_BUCKET" ] && existe_bucket "$RAW_BUCKET"; then
    aws s3api delete-bucket --region "$REGION" --bucket "$RAW_BUCKET" \
      && echo "   borrado el bucket $RAW_BUCKET"
  fi
  if [ -n "$TABLE_BUCKET_ARN" ]; then
    for ns in silver gold; do
      aws s3tables delete-namespace --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
        --namespace "$ns" 2>/dev/null && echo "   borrado el namespace $ns" || true
    done
    aws s3tables delete-table-bucket --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
      && echo "   borrado el table bucket $TABLE_BUCKET"
  fi
  # Lo que se crea a mano en la consola (labs/manual-consola) y no tiene stack
  # que lo borre: jobs, workgroup, rol IAM y presupuesto.
  for job in "$JOB_SILVER" "$JOB_GOLD" "$JOB_LAB4"; do
    if aws glue get-job --region "$REGION" --job-name "$job" >/dev/null 2>&1; then
      aws glue delete-job --region "$REGION" --job-name "$job" >/dev/null && echo "   borrado el job $job"
    fi
  done
  if aws athena get-work-group --region "$REGION" --work-group "$WORKGROUP" >/dev/null 2>&1; then
    aws athena delete-work-group --region "$REGION" --work-group "$WORKGROUP" \
      --recursive-delete-option && echo "   borrado el workgroup $WORKGROUP"
  fi
  if aws iam get-role --role-name "$ROLE_GLUE" >/dev/null 2>&1; then
    for politica in $(aws iam list-role-policies --role-name "$ROLE_GLUE" \
                        --query 'PolicyNames[]' --output text 2>/dev/null || true); do
      [ "$politica" = "None" ] && continue
      aws iam delete-role-policy --role-name "$ROLE_GLUE" --policy-name "$politica"
    done
    for arn in $(aws iam list-attached-role-policies --role-name "$ROLE_GLUE" \
                   --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || true); do
      [ "$arn" = "None" ] && continue
      aws iam detach-role-policy --role-name "$ROLE_GLUE" --policy-arn "$arn"
    done
    aws iam delete-role --role-name "$ROLE_GLUE" && echo "   borrado el rol $ROLE_GLUE"
  fi
  if aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name "$BUDGET" >/dev/null 2>&1; then
    aws budgets delete-budget --account-id "$ACCOUNT_ID" --budget-name "$BUDGET" \
      && echo "   borrado el presupuesto $BUDGET"
  fi
fi

verde "Listo: no queda nada que cobre."
echo "Se conserva a proposito el catalogo 's3tablescatalog' de Glue (compartido, sin costo)."
echo "Los CSV locales de data/sample/ puedes borrarlos con:  rm -rf data/sample"
