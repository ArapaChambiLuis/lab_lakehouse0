#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Lakehouse escalable en AWS - Aseguradora Andina S.A. (ficticia)
#  Despliega TODO con un solo comando:
#
#     ./deploy.sh
#
#  Opciones:
#     --hasta <etapa>   infra | bronze | silver | gold | lab4 (por defecto: lab4 = todo)
#                       Rescate: si te atrasaste, ./deploy.sh --hasta silver te deja
#                       listo para empezar el Lab 3.
#     --region <r>      Region AWS (por defecto: us-east-1)
#     --proyecto <p>    Codigo del proyecto (por defecto: lkh)
#     --entorno <e>     Entorno: lab, dev, qa, prd (por defecto: lab)
#     --owner <o>       Tag Owner (por defecto: tu usuario de AWS)
#     --email <e>       Crea una alerta de presupuesto de 5 USD a ese correo
#
#  Para ir lab por lab en el workshop usa ./lab.sh <0-4>
# ------------------------------------------------------------------
set -euo pipefail
export AWS_PAGER=""

RAIZ="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/comun.sh
source "$RAIZ/scripts/comun.sh"
# shellcheck source=scripts/etapas.sh
source "$RAIZ/scripts/etapas.sh"

REGION="${AWS_REGION:-us-east-1}"
EMAIL=""
HASTA="lab4"

while [ $# -gt 0 ]; do
  case "$1" in
    --hasta)   HASTA="$2"; shift 2 ;;
    --region)  REGION="$2"; shift 2 ;;
    --proyecto) PROYECTO="$2"; shift 2 ;;
    --entorno) ENTORNO="$2"; shift 2 ;;
    --owner)   OWNER="$2"; shift 2 ;;
    --email)   EMAIL="$2"; shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) morir "Opcion desconocida: $1 (usa --help)" ;;
  esac
done

case "$HASTA" in
  infra) NIVEL=0 ;; bronze) NIVEL=1 ;; silver) NIVEL=2 ;; gold) NIVEL=3 ;; lab4) NIVEL=4 ;;
  *) morir "--hasta debe ser: infra, bronze, silver, gold o lab4" ;;
esac

INICIO_TOTAL=$(date +%s)

paso "Verificando requisitos"
verificar_requisitos
verde "   Cuenta $ACCOUNT_ID | region $REGION | nombres: ${BASE}-* | hasta: $HASTA"

etapa_infra
[ "$NIVEL" -ge 1 ] && etapa_bronze
[ "$NIVEL" -ge 2 ] && { etapa_silver || exit 1; }
[ "$NIVEL" -ge 3 ] && { etapa_gold || exit 1; }
[ "$NIVEL" -ge 4 ] && { etapa_lab4 || exit 1; }

MINUTOS=$(( ($(date +%s) - INICIO_TOTAL) / 60 ))
cat <<EOF

$(verde "Listo hasta '$HASTA' en ~${MINUTOS} min")
  Bronze (S3):        s3://$RAW_BUCKET/bronze/
  Silver/Gold:        table bucket $TABLE_BUCKET
  Athena workgroup:   $WORKGROUP
  Catalogo en Athena: $CATALOGO_TABLES  (bases: silver, gold)

  Siguiente paso: abre la guia del lab en labs/ o continua con ./lab.sh <n>

$(amarillo "Cuando termines:  ./cleanup.sh   (deja la cuenta en 0)")
EOF
