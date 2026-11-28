#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Ejecuta UN lab del workshop. Sigue la guia de cada lab en labs/.
#
#     ./lab.sh 0    Infraestructura (CloudFormation)
#     ./lab.sh 1    Bronze  - datos crudos en S3 + Athena
#     ./lab.sh 2    Silver  - Glue limpia y escribe Iceberg en S3 Tables
#     ./lab.sh 3    Gold    - indicadores de negocio
#     ./lab.sh 4    Auditoria - evolucion de esquema + time travel
#     ./lab.sh estado   Que labs tienes hechos y cual sigue
#
#  Funciona igual si creaste la infraestructura por script (./lab.sh 0) o a
#  mano en la consola (labs/manual-consola): en ese caso usa tus recursos.
#
#  Opciones: --region <r>  --proyecto <p>  --entorno <e>  --owner <o>  --email <e> (solo lab 0)
#            --reiniciar (solo lab 0: borra lo creado a mano y despliega por script)
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
REINICIAR="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --region)  REGION="$2"; shift 2 ;;
    --proyecto) PROYECTO="$2"; shift 2 ;;
    --entorno) ENTORNO="$2"; shift 2 ;;
    --owner)   OWNER="$2"; shift 2 ;;
    --email)   EMAIL="$2"; shift 2 ;;
    --reiniciar) REINICIAR="si"; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    [0-4]|estado) LAB="$1"; shift ;;
    *) morir "Argumento no valido: $1  (usa: ./lab.sh <0-4|estado>)" ;;
  esac
done
[ -n "$LAB" ] || { sed -n '2,18p' "$0"; exit 1; }

verificar_requisitos
resolver_recursos

if [ "$LAB" = "estado" ]; then
  mostrar_estado
  exit 0
fi

faltante() {  # faltante <lab-que-falta> <etapa-para-deploy>
  rojo "Antes necesitas el Lab $1."
  echo "  Hazlo con:        ./lab.sh $1   (o en la consola: labs/manual-consola)"
  echo "  O ponte al dia:   ./deploy.sh --hasta $2"
  echo "  Para ver donde estas:  ./lab.sh estado"
  exit 1
}

# ---------------- Lab 0 ----------------
if [ "$LAB" = "0" ]; then
  if [ "$MODO" = "consola" ]; then
    if [ "$REINICIAR" != "si" ]; then
      amarillo "Ya tienes recursos creados a mano en la consola (no hay stack $STACK)."
      echo "  - Si terminaste la infraestructura en la consola, sigue con:  ./lab.sh 1"
      echo "    (./lab.sh estado te dice si te falta algo)"
      echo "  - Si te perdiste a mitad de camino:  ./lab.sh 0 --reiniciar"
      echo "    Borra lo que creaste a mano con los nombres del estandar y despliega todo por script (~4 min)."
      exit 1
    fi
    paso "Reiniciando: borro lo creado a mano para desplegar por script"
    "$RAIZ/cleanup.sh" --si --region "$REGION" --proyecto "$PROYECTO" --entorno "$ENTORNO"
  fi
  etapa_infra
  echo
  verde "Lab 0 completado."
  echo "Siguiente: labs/lab1-bronze/README.md  ->  ./lab.sh 1"
  exit 0
fi

# ---------------- Labs 1 a 4 ----------------
case "$MODO" in
  ninguno) faltante 0 infra ;;
  consola)
    verde "   Uso la infraestructura que creaste en la consola (${BASE}-*)"
    revisar_infra_consola "$LAB" || exit 1 ;;
esac
if [ "$LAB" -ge 2 ]; then existe_bronze || faltante 1 bronze; fi
if [ "$LAB" -ge 3 ]; then existe_tabla silver siniestros || faltante 2 silver; fi
if [ "$LAB" -ge 4 ]; then existe_tabla gold agg_siniestralidad_producto_anual || faltante 3 gold; fi

case "$LAB" in
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
  echo "Siguiente: labs/lab5-gobierno/README.md (opcional) y, al final, ./cleanup.sh"
fi
