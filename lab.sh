#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Ejecuta UN lab del workshop. Sigue la guia de cada lab en labs/.
#
#     ./lab.sh 0    Infraestructura (CloudFormation)
#     ./lab.sh 1    Bronze  - datos crudos en S3 + Athena
#     ./lab.sh 2    Silver  - Glue limpia y escribe Iceberg en S3 Tables
#     ./lab.sh 3    Gold    - indicadores de negocio
#     ./lab.sh 4    Auditoria - evolucion de esquema + time travel
#
#  Opciones: --region <r>  --proyecto <p>  --entorno <e>  --owner <o>  --email <e> (solo lab 0)
#  Si te falta un lab anterior, el script te dice como ponerte al dia.
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
LAB=""

while [ $# -gt 0 ]; do
  case "$1" in
    --region)  REGION="$2"; shift 2 ;;
    --proyecto) PROYECTO="$2"; shift 2 ;;
    --entorno) ENTORNO="$2"; shift 2 ;;
    --owner)   OWNER="$2"; shift 2 ;;
    --email)   EMAIL="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    [0-4])     LAB="$1"; shift ;;
    *) morir "Argumento no valido: $1  (usa: ./lab.sh <0-4>)" ;;
  esac
done
[ -n "$LAB" ] || { sed -n '2,14p' "$0"; exit 1; }

verificar_requisitos

faltante() {  # faltante <lab-que-falta> <etapa-para-deploy>
  rojo "Antes necesitas el Lab $1."
  echo "  Hazlo con:        ./lab.sh $1"
  echo "  O ponte al dia:   ./deploy.sh --hasta $2"
  exit 1
}

if [ "$LAB" -ge 1 ]; then
  existe_stack || faltante 0 infra
  cargar_salidas
fi
if [ "$LAB" -ge 2 ]; then existe_bronze || faltante 1 bronze; fi
if [ "$LAB" -ge 3 ]; then existe_tabla silver siniestros || faltante 2 silver; fi
if [ "$LAB" -ge 4 ]; then existe_tabla gold agg_siniestralidad_producto_anual || faltante 3 gold; fi

case "$LAB" in
  0) etapa_infra ;;
  1) etapa_bronze ;;
  2) etapa_silver ;;
  3) etapa_gold ;;
  4) etapa_lab4 ;;
esac

echo
verde "Lab $LAB completado."
if [ "$LAB" -lt 4 ]; then
  echo "Siguiente: labs/lab$(( LAB + 1 ))*/README.md  ->  ./lab.sh $(( LAB + 1 ))"
else
  echo "Siguiente: labs/lab5-gobierno/README.md (demo) y, al final, ./cleanup.sh"
fi
