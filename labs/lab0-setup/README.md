# Lab 0 · Setup

## 🎯 Objetivo
Dejar tu cuenta lista y protegida: infraestructura como código y una alerta de costos.

## ▶️ Ejecutar
1. Abre **AWS CloudShell** (ícono `>_` arriba a la derecha en la consola). Verifica que la región sea **N. Virginia (us-east-1)**.
2. Clona el repo y lanza el lab:
   ```bash
   git clone <URL-del-repo> && cd lakehouse-aseguradora-aws
   ./lab.sh 0 --email tu@correo.com
   ```
   El `--email` es opcional, pero recomendado: crea una alerta si gastas más de 2.5 USD (50% de 5 USD).
3. **Revisa tu correo** y confirma la suscripción de AWS Budgets.

## 🔍 Qué pasó por detrás
`infra/template.yaml` creó en un solo stack:
- Un **bucket S3** para Bronze, los scripts y los resultados de Athena (privado y cifrado).
- Un **table bucket de S3 Tables** con dos namespaces: `silver` y `gold`.
- Tres **jobs de Glue 5.0**, uno por lab, y un **rol IAM** con permisos mínimos.
- Un **workgroup de Athena** con un tope de 1 GB escaneado por consulta, que te protege de una consulta cara.

Además, se activó la integración **S3 Tables ↔ Glue Data Catalog**, para que Athena pueda ver tus tablas Iceberg.

**Fíjate en los nombres:** todo sigue el patrón `{proyecto}-{entorno}-{componente}` (`lkh-lab-tables`, `lkh-lab-job-bronze-to-silver`...) y lleva los tags `Proyecto`, `Entorno`, `Owner` y `CentroCosto`. Si mañana despliegas `--entorno dev`, conviven sin chocar. El estándar completo está en la sección *Nomenclatura y tags* del README principal.

## ✅ Verificar en la consola
- **CloudFormation** → stack `lkh-lab-stack` en `CREATE_COMPLETE`. Abre la pestaña *Resources*.
- **S3** → *Table buckets* → `lkh-lab-tables` → namespaces `silver` y `gold` (todavía vacíos).
- **S3** → tu bucket `lkh-lab-raw-...` → pestaña *Properties* → *Tags*: ahí están `Proyecto`, `Entorno`, `Owner`, `CentroCosto` y `Clasificacion`.

## 💬 Para pensar
- ¿Qué pasaría en tu empresa si estos recursos se crearan a mano en la consola? ¿Cómo lo replicarías en QA y en producción?
- ¿Por qué un tope de bytes escaneados en Athena es una buena práctica en banca y seguros?

➡️ Siguiente: [Lab 1 · Bronze](../lab1-bronze/README.md)
