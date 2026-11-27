#!/usr/bin/env bash
# Las etapas del workshop, una funcion por lab. Las usan deploy.sh (todas
# seguidas) y lab.sh (una sola). Requiere haber cargado scripts/comun.sh y
# definido REGION, EMAIL y RAIZ (los nombres los arma configurar_nombres).

# ---------------- Lab 0: infraestructura ----------------
etapa_infra() {
  paso "Lab 0 · Infraestructura (CloudFormation, ~2-3 min)"
  python3 "$RAIZ/data/generator.py" --out "$RAIZ/data/sample" >/dev/null
  aws cloudformation deploy --region "$REGION" \
    --stack-name "$STACK" \
    --template-file "$RAIZ/infra/template.yaml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides "Proyecto=$PROYECTO" "Entorno=$ENTORNO" "EmailAlerta=${EMAIL:-}" \
    --tags "Proyecto=lakehouse-aseguradora" "Entorno=$ENTORNO" "Owner=${OWNER:-sin-owner}" \
           "CentroCosto=$CENTRO_COSTO"
  cargar_salidas
  MODO="script"
  verde "   Stack $STACK listo"
  asegurar_catalogo
  subir_scripts
}

# Integracion de S3 Tables con Glue Data Catalog (para que Athena vea Silver/Gold).
# Una vez por cuenta y region; si ya existe, no se toca. Es lo mismo que la
# casilla "Enable integration" al crear el table bucket en la consola.
asegurar_catalogo() {
  if aws glue get-catalog --region "$REGION" --catalog-id s3tablescatalog >/dev/null 2>&1; then
    verde "   Integracion S3 Tables <-> Glue Data Catalog: ya existia"
  else
    local catalogo_json
    catalogo_json=$(mktemp)
    cat > "$catalogo_json" <<EOF
{
  "Name": "s3tablescatalog",
  "CatalogInput": {
    "FederatedCatalog": {
      "Identifier": "arn:aws:s3tables:${REGION}:${ACCOUNT_ID}:bucket/*",
      "ConnectionName": "aws:s3tables"
    },
    "CreateDatabaseDefaultPermissions": [
      {"Principal": {"DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"}, "Permissions": ["ALL"]}
    ],
    "CreateTableDefaultPermissions": [
      {"Principal": {"DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"}, "Permissions": ["ALL"]}
    ],
    "AllowFullTableExternalDataAccess": "True"
  }
}
EOF
    aws glue create-catalog --region "$REGION" --cli-input-json "file://$catalogo_json" >/dev/null
    rm -f "$catalogo_json"
    verde "   Integracion S3 Tables <-> Glue Data Catalog: creada"
  fi
}

subir_scripts() {
  aws s3 cp "$RAIZ/glue/" "s3://$RAW_BUCKET/scripts/" --recursive \
    --exclude "*" --include "*.py" --only-show-errors
}

# ---------------- Lab 1: Bronze ----------------
etapa_bronze() {
  paso "Lab 1 · Bronze: datos crudos a S3 + tablas en Athena (~1 min)"
  [ -f "$RAIZ/data/sample/siniestros.csv" ] || python3 "$RAIZ/data/generator.py" --out "$RAIZ/data/sample" >/dev/null
  local tabla
  for tabla in clientes polizas pagos_primas siniestros; do
    aws s3 cp "$RAIZ/data/sample/$tabla.csv" "s3://$RAW_BUCKET/bronze/$tabla/$tabla.csv" --only-show-errors
    echo "   subido bronze/$tabla/"
  done
  # Cada sentencia del DDL por separado (Athena acepta una por llamada)
  local sentencia
  while IFS= read -r -d '' sentencia; do
    athena "$sentencia" </dev/null || morir "Fallo el DDL de Bronze"
  done < <(python3 - "$RAIZ/sql/bronze_ddl.sql" "$RAW_BUCKET" "$DB_BRONZE" <<'PY'
import sys
sql = (open(sys.argv[1], encoding="utf-8").read()
       .replace("__RAW_BUCKET__", sys.argv[2]).replace("__DB_BRONZE__", sys.argv[3]))
lineas = [l for l in sql.splitlines() if not l.strip().startswith("--")]
for s in "\n".join(lineas).split(";"):
    if s.strip():
        sys.stdout.write(s.strip() + "\0")
PY
)
  verde "   Base $DB_BRONZE creada con 4 tablas"
  echo "   Estados de siniestro tal como llegaron (fijate en el desorden):"
  athena_tabla "SELECT estado, count(*) AS n FROM $DB_BRONZE.siniestros GROUP BY estado ORDER BY n DESC"
}

# ---------------- Lab 2: Silver ----------------
etapa_silver() {
  paso "Lab 2 · Silver: Glue limpia y escribe Iceberg en S3 Tables (~3-5 min)"
  subir_scripts   # por si editaste glue/bronze_to_silver.py durante el lab
  correr_glue "$JOB_SILVER" || return 1
  echo "   Estados de siniestro despues de limpiar:"
  athena_tabla "SELECT estado, count(*) AS n FROM siniestros GROUP BY estado ORDER BY n DESC" \
    "$CATALOGO_TABLES" silver || amarillo "   (Athena aun no ve Silver: revisa 'Problemas comunes' en el README)"
}

# ---------------- Lab 3: Gold ----------------
etapa_gold() {
  paso "Lab 3 · Gold: indicadores de negocio (~3 min)"
  subir_scripts
  correr_glue "$JOB_GOLD" || return 1
  echo "   Siniestralidad por producto (siniestros pagados / primas cobradas):"
  athena_tabla "SELECT producto, anio, primas_cobradas, siniestros_pagados, ratio_siniestralidad
                FROM agg_siniestralidad_producto_anual ORDER BY anio DESC, ratio_siniestralidad DESC" \
    "$CATALOGO_TABLES" gold || true
}

# ---------------- Lab 4: auditoria ----------------
etapa_lab4() {
  paso "Lab 4 · Evolucion de esquema + correccion + time travel (~3 min)"
  subir_scripts
  ANTES=$(date -u '+%Y-%m-%d %H:%M:%S')
  sleep "${LAKEHOUSE_PAUSA_LAB4:-2}"
  correr_glue "$JOB_LAB4" || return 1
  echo "   AHORA:"
  athena_tabla "SELECT id_siniestro, estado, monto_pagado, flag_fraude FROM siniestros WHERE id_siniestro = 'SIN-00042'" \
    "$CATALOGO_TABLES" silver || true
  echo "   ANTES (time travel a $ANTES UTC):"
  athena_tabla "SELECT id_siniestro, estado, monto_pagado FROM siniestros
                FOR TIMESTAMP AS OF TIMESTAMP '$ANTES UTC' WHERE id_siniestro = 'SIN-00042'" \
    "$CATALOGO_TABLES" silver || true
  echo
  echo "   Copia esta consulta para la consola de Athena:"
  echo "   SELECT * FROM silver.siniestros FOR TIMESTAMP AS OF TIMESTAMP '$ANTES UTC' WHERE id_siniestro = 'SIN-00042';"
}

# ---------------- infraestructura creada a mano en la consola ----------------
# Cuando no hay stack (MODO=consola), los labs usan los recursos que creaste
# siguiendo labs/manual-consola. revisar_infra_consola <lab> revisa pieza por
# pieza lo que ese lab necesita:
#   - lo que es seguro e idempotente lo completa solo (namespaces, integracion
#     con Athena, scripts en S3);
#   - lo demas lo reporta con el paso del manual donde se crea, y tambien avisa
#     si un job de Glue quedo mal configurado (el error mas comun a mano).
# Devuelve 1 si falta algo que el lab necesita.
revisar_infra_consola() {
  local lab="$1" faltan="" job archivo esperado salida ns
  local script_ok glue_ok formato_ok arn_ok raw_ok region_ok

  existe_bucket "$RAW_BUCKET" || faltan="${faltan}
   - Bucket S3 $RAW_BUCKET  (manual: paso 2.1)"

  if aws athena get-work-group --region "$REGION" --work-group "$WORKGROUP" >/dev/null 2>&1; then
    salida=$(aws athena get-work-group --region "$REGION" --work-group "$WORKGROUP" \
      --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text 2>/dev/null || true)
    case "$salida" in
      s3://*) ;;
      *) faltan="${faltan}
   - El workgroup $WORKGROUP no tiene 'Location of query result'  (manual: paso 6)" ;;
    esac
  else
    faltan="${faltan}
   - Workgroup de Athena $WORKGROUP  (manual: paso 6)"
  fi

  if [ "$lab" -ge 2 ]; then
    if [ -z "$TABLE_BUCKET_ARN" ]; then
      faltan="${faltan}
   - Table bucket $TABLE_BUCKET  (manual: paso 3.1)"
    else
      for ns in silver gold; do
        if ! aws s3tables get-namespace --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
             --namespace "$ns" >/dev/null 2>&1; then
          aws s3tables create-namespace --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
            --namespace "$ns" >/dev/null && verde "   namespace $ns: no existia, lo cree (paso 3.2 del manual)"
        fi
      done
    fi
    aws iam get-role --role-name "$ROLE_GLUE" >/dev/null 2>&1 || faltan="${faltan}
   - Rol IAM $ROLE_GLUE  (manual: paso 4)"

    for job in "$JOB_SILVER" "$JOB_GOLD" "$JOB_LAB4"; do
      case "$job" in
        "$JOB_SILVER") archivo="bronze_to_silver.py" ;;
        "$JOB_GOLD")   [ "$lab" -ge 3 ] || continue; archivo="silver_to_gold.py" ;;
        "$JOB_LAB4")   [ "$lab" -ge 4 ] || continue; archivo="silver_auditoria.py" ;;
      esac
      if ! aws glue get-job --region "$REGION" --job-name "$job" >/dev/null 2>&1; then
        faltan="${faltan}
   - Job de Glue $job  (manual: paso 5)"
        continue
      fi
      # Una sola llamada: script, version y parametros, separados por tabs
      salida=$(aws glue get-job --region "$REGION" --job-name "$job" --output text --query \
        '[Job.Command.ScriptLocation, Job.GlueVersion, Job.DefaultArguments."--datalake-formats", Job.DefaultArguments."--TABLE_BUCKET_ARN", Job.DefaultArguments."--RAW_BUCKET", Job.DefaultArguments."--AWS_REGION_NAME"]' \
        2>/dev/null || true)
      IFS=$'\t' read -r script_ok glue_ok formato_ok arn_ok raw_ok region_ok <<< "$salida" || true
      esperado="s3://$RAW_BUCKET/scripts/$archivo"
      [ "${script_ok:-}" = "$esperado" ] || faltan="${faltan}
   - $job: el script debe ser $esperado (tiene: ${script_ok:-ninguno})  (manual: paso 5.1)"
      [ "${glue_ok:-}" = "5.0" ] || faltan="${faltan}
   - $job: Glue version debe ser 5.0 (tiene: ${glue_ok:-ninguna})  (manual: paso 5.1)"
      [ "${formato_ok:-}" = "iceberg" ] || faltan="${faltan}
   - $job: falta el parametro --datalake-formats = iceberg  (manual: paso 5.1)"
      [ "${arn_ok:-}" = "$TABLE_BUCKET_ARN" ] || faltan="${faltan}
   - $job: --TABLE_BUCKET_ARN debe ser ${TABLE_BUCKET_ARN:-el ARN del table bucket} (tiene: ${arn_ok:-ninguno})  (manual: paso 5.1)"
      [ "${region_ok:-}" = "$REGION" ] || faltan="${faltan}
   - $job: --AWS_REGION_NAME debe ser $REGION (tiene: ${region_ok:-ninguno})  (manual: paso 5.1)"
      if [ "$job" = "$JOB_SILVER" ] && [ "${raw_ok:-}" != "$RAW_BUCKET" ]; then
        faltan="${faltan}
   - $job: --RAW_BUCKET debe ser $RAW_BUCKET (tiene: ${raw_ok:-ninguno})  (manual: paso 5.1)"
      fi
    done
  fi

  if [ -n "$faltan" ]; then
    rojo "Tu infraestructura de la consola no esta completa para el Lab $lab:"
    printf '%s\n' "$faltan" | sed '/^$/d' >&2
    echo
    echo "  Corrigelo en la consola siguiendo labs/manual-consola, o pasate a la ruta por script:"
    echo "     ./lab.sh 0 --reiniciar   (borra lo creado a mano y despliega todo por script, ~4 min)"
    return 1
  fi
  asegurar_catalogo
  subir_scripts
  return 0
}

# ---------------- chequeos de prerequisitos para lab.sh ----------------
# existe_stack() y existe_bucket() viven en comun.sh: tambien los usa cleanup.sh.

existe_tabla() {  # existe_tabla <namespace> <tabla>
  [ -n "${TABLE_BUCKET_ARN:-}" ] || return 1
  aws s3tables get-table --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
    --namespace "$1" --name "$2" >/dev/null 2>&1
}

existe_bronze() {
  aws s3 ls "s3://$RAW_BUCKET/bronze/siniestros/" >/dev/null 2>&1
}

existe_bronze_athena() {
  aws glue get-table --region "$REGION" --database-name "$DB_BRONZE" --name siniestros >/dev/null 2>&1
}

# El Lab 4 agrega la columna flag_fraude: si Athena la encuentra, el lab se hizo.
lab4_hecho() {
  [ -n "${TABLE_BUCKET_ARN:-}" ] || return 1
  athena "SELECT flag_fraude FROM siniestros WHERE id_siniestro = 'SIN-00042'" \
    "$CATALOGO_TABLES" silver >/dev/null 2>&1
}

# ---------------- ./lab.sh estado ----------------
# Le dice a quien se perdio en que punto esta y que comando lo pone al dia.
mostrar_estado() {
  local siguiente=""
  marca() { if "$@"; then printf '\033[32m✔ hecho\033[0m'; else printf '\033[33m· pendiente\033[0m'; fi; }

  paso "Estado de tu Lakehouse ($BASE en $REGION)"
  case "$MODO" in
    script)  echo "   Origen: CloudFormation (stack $STACK)" ;;
    consola) echo "   Origen: creado a mano en la consola (sin stack)" ;;
    ninguno) echo "   Origen: todavia no hay nada creado" ;;
  esac
  echo

  if [ "$MODO" = "ninguno" ]; then
    printf '   Lab 0 · Infraestructura  '; marca false; echo
    siguiente="./lab.sh 0   (o el manual por consola, pasos 1 a 6)"
  else
    printf '   Lab 0 · Infraestructura  '
    if [ "$MODO" = "script" ] || revisar_infra_consola 4 >/dev/null 2>&1; then
      marca true; echo
    else
      marca false; echo "   -> ./lab.sh 1 te dira que falta"
      siguiente="completar la infraestructura en la consola, o ./lab.sh 0 --reiniciar"
    fi
    printf '   Lab 1 · Bronze           '; marca existe_bronze_athena; echo
    printf '   Lab 2 · Silver           '; marca existe_tabla silver siniestros; echo
    printf '   Lab 3 · Gold             '; marca existe_tabla gold agg_siniestralidad_producto_anual; echo
    printf '   Lab 4 · Auditoria        '; marca lab4_hecho; echo

    if [ -z "$siguiente" ]; then
      if ! existe_bronze_athena; then siguiente="./lab.sh 1"
      elif ! existe_tabla silver siniestros; then siguiente="./lab.sh 2"
      elif ! existe_tabla gold agg_siniestralidad_producto_anual; then siguiente="./lab.sh 3"
      elif ! lab4_hecho; then siguiente="./lab.sh 4"
      else siguiente="labs/lab5-gobierno (demo) y, al final, ./cleanup.sh"
      fi
    fi
  fi
  echo
  verde "   Siguiente paso: $siguiente"
  echo "   Para alcanzar al grupo de una vez:  ./deploy.sh --hasta <bronze|silver|gold|lab4>"
}
