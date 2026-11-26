# Lab 5 · Gobierno (demo del presentador)

## 🎯 Objetivo
Entender cómo se protegen los datos personales del asegurado: **cada rol ve solo lo que necesita**.

## ⚠️ Por qué es una demo y no un lab
El despliegue usa la integración de S3 Tables con **control de acceso por IAM**, que es la opción por defecto y la más simple. Para dar permisos **por columna**, hay que pasar la integración a **AWS Lake Formation**. Ese cambio afecta la configuración de toda la cuenta, así que no conviene automatizarlo en las cuentas de los asistentes. Lo hace el presentador en su propia cuenta.

## 🧩 Lo que ya tienes aplicado
- **Separación por capas:** Silver tiene PII (`clientes.dni`, `nombre`, `email`); Gold no.
- **Gold sin PII:** `gold.agg_cartera_region_producto` agrega por departamento y producto, sin un solo dato personal.
- **Mínimo privilegio:** el rol de Glue solo accede a su bucket y a su table bucket (revisa `GlueRole` en `infra/template.yaml`).

Compruébalo en Athena:
```sql
-- silver: hay PII
SELECT * FROM silver.clientes LIMIT 5;
-- gold: no hay forma de identificar a una persona
SELECT * FROM gold.agg_cartera_region_producto LIMIT 5;
```

## 🎬 Guion de la demo (para el presentador)
**Prepáralo en tu cuenta antes del evento.** Consulta la guía oficial: *"Amazon S3 Tables integration with AWS Glue Data Catalog and AWS Lake Formation"* en la AWS Lake Formation Developer Guide.

1. En **Lake Formation**, registrarte como *data lake administrator*.
2. Pasar el catálogo `s3tablescatalog` a control de acceso con Lake Formation, siguiendo la guía oficial.
3. Crear un rol `analista-riesgos`.
4. En *Data permissions* → *Grant*, darle `SELECT` sobre `silver.clientes` **solo** en las columnas `id_cliente` y `departamento`, y `SELECT` completo sobre la base `gold`.
5. Cambiar al rol `analista-riesgos` y ejecutar en Athena:
   - `SELECT * FROM silver.clientes` → solo se ven las columnas permitidas (o error si se piden las prohibidas).
   - `SELECT * FROM gold.agg_cartera_region_producto` → funciona normal.

**Mensaje para el público:** el mismo dato, la misma tabla y el mismo motor (Athena), pero cada rol ve algo distinto, definido en un solo lugar. Eso es lo que pide un oficial de seguridad o protección de datos.

## 💬 Para pensar
- En la Ley de Protección de Datos Personales de tu país, ¿qué datos de esta tabla se consideran sensibles?
- ¿Quién debería aprobar un permiso sobre `silver.clientes` en tu empresa?

➡️ Para terminar: `./cleanup.sh` y [llévalo a tu CV](../../README.md#-llévalo-a-tu-cv)
