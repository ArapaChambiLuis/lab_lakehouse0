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
  verde "   Stack $STACK listo"

  # Integracion de S3 Tables con Glue Data Catalog (para que Athena vea Silver/Gold).
  # Una vez por cuenta y region; si ya existe, no se toca.
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

  subir_scripts
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
  sleep 2
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

# ---------------- chequeos de prerequisitos para lab.sh ----------------
# existe_stack() vive en comun.sh: tambien lo usa cleanup.sh.

existe_tabla() {  # existe_tabla <namespace> <tabla>
  aws s3tables get-table --region "$REGION" --table-bucket-arn "$TABLE_BUCKET_ARN" \
    --namespace "$1" --name "$2" >/dev/null 2>&1
}

existe_bronze() {
  aws s3 ls "s3://$RAW_BUCKET/bronze/siniestros/" >/dev/null 2>&1
}
