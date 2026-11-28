# Lab 4 · Respuestas a "Para pensar"

Respuestas de referencia para las dos preguntas de discusión del [Lab 4](README.md). Sirven para guiar la conversación en la sesión; no son asesoría legal.

---

## 1. ¿Cuánto tiempo pide guardar historia el regulador? ¿Cómo lo configurarías?

### El plazo

- **Sistema financiero y de seguros (Perú):** la norma pide conservar libros y documentos por un plazo **no menor de diez años**. Viene de la Ley 26612 (1996), que modificó la ley general de instituciones bancarias, financieras y de seguros de entonces.
- **Tributario:** la acción para aplicar sanciones prescribe a los 4 años, o a los 6 si no se presentó la declaración.

El plazo exacto de cada dato lo define el área de cumplimiento. En la sesión basta con quedarse con "10 años".

### Lo que hace S3 Tables por defecto

La gestión de snapshots viene activada con valores muy cortos:

| Parámetro | Valor por defecto | Qué significa |
|---|---|---|
| `minSnapshotsToKeep` | 1 | Nunca baja de 1 versión |
| `maxSnapshotAgeHours` | 120 | Los snapshots con más de 5 días pueden expirar |

Un snapshot expira cuando **supera la edad máxima y además** la tabla tiene más versiones que el mínimo. Con los valores por defecto, el time travel del lab funciona más o menos **5 días**.

### Cómo configurarlo

Por ejemplo, 90 días de time travel y nunca menos de 10 versiones:

```bash
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn <arn-del-table-bucket> \
  --namespace silver --name siniestros \
  --type icebergSnapshotManagement \
  --value '{"status":"enabled","settings":{"icebergSnapshotManagement":{"minSnapshotsToKeep":10,"maxSnapshotAgeHours":2160}}}'
```

Para ver la configuración actual:

```bash
aws s3tables get-table-maintenance-configuration \
  --table-bucket-arn <arn-del-table-bucket> \
  --namespace silver --name siniestros
```

### El matiz importante: los snapshots no son el archivo de 10 años

Mientras un snapshot existe, sus archivos de datos no se pueden borrar. Guardar 10 años de snapshots de una tabla que cambia todos los días sale caro y vuelve lentas las consultas de metadatos. Por eso conviene separarlo en dos niveles:

| Nivel | Retención | Para qué sirve |
|---|---|---|
| **Snapshots de Iceberg** | 90 días a 13 meses | Uso operativo: reprocesos, correcciones y auditorías recientes |
| **Fotos de cierre** | 10 años | Evidencia regulatoria |

Las fotos de cierre van en una tabla de solo inserción (por ejemplo `siniestros_cierre`, con una columna `periodo`). Cada cierre mensual agrega la foto completa del mes, y nunca se actualiza ni se borra. Esa tabla se puede llevar a almacenamiento más barato.

> Time travel no reemplaza a tu política de retención: es una máquina del tiempo de corto plazo. Para la evidencia regulatoria de 10 años, diseña fotos de cierre.

---

## 2. ¿Qué otros casos se resolverían con time travel?

| Caso | Pregunta que responde |
|---|---|
| **Cierres contables** | ¿Con qué datos exactos se calculó el reporte de reservas de siniestros que enviamos a la SBS? |
| **Reclamos de clientes** | ¿La póliza estaba vigente el día del siniestro, antes de los endosos y anulaciones posteriores? |
| **Reprocesos** | Un job dañó los datos: ¿qué cambió entre la versión anterior y la actual? ¿Volvemos atrás sin restaurar backups? |
| **Fraude y auditoría** | ¿Quién cambió el estado de este siniestro y cuándo? (como el `SIN-00042` del lab) |
| **Rectificaciones regulatorias** | La SBS observó un reporte: ¿qué se envió originalmente y qué se corrigió? |
| **Modelos de ML reproducibles** | ¿Con qué datos se entrenó el modelo de fraude o de tarificación? ¿Podemos repetir el entrenamiento meses después? |
| **Calidad de datos** | El KPI de Gold cambió de un día para otro: ¿en qué carga empezó el problema? |

Consultas que sirven como punto de partida en Athena (catálogo `s3tablescatalog/lkh-lab-tables`, base `silver`):

```sql
-- Versiones disponibles de la tabla
SELECT * FROM "siniestros$history";
```

```sql
-- La tabla como estaba en una fecha
SELECT estado, count(*) AS n
FROM siniestros FOR TIMESTAMP AS OF TIMESTAMP '2026-11-28 15:00:00 UTC'
GROUP BY estado;
```

---

### Fuentes

- [AWS · Maintenance for tables (S3 Tables)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-maintenance.html)
- [AWS · IcebergSnapshotManagementSettings](https://docs.aws.amazon.com/AmazonS3/latest/API/API_s3Buckets_IcebergSnapshotManagementSettings.html)
- [Ley 26612 (1996), conservación de libros y documentos](https://peru.justia.com/federales/leyes/26612-may-17-1996/gdoc)
- [SUNAT · Informe 023-2019 sobre plazos de prescripción](https://www.sunat.gob.pe/legislacion/oficios/2019/informe-oficios/i023-2019-7T0000.pdf)
