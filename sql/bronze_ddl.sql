-- Lab 1 - Capa BRONZE
-- Tablas externas sobre los CSV crudos. Todo es STRING a proposito:
-- en Bronze guardamos el dato tal como llego, sin interpretar.
-- Los scripts reemplazan __DB_BRONZE__ (ej: lkh_lab_bronze), __RAW_BUCKET__ y ejecuta cada sentencia en Athena.

CREATE DATABASE IF NOT EXISTS __DB_BRONZE__;

CREATE EXTERNAL TABLE IF NOT EXISTS __DB_BRONZE__.clientes (
  id_cliente string, dni string, nombre string, email string,
  departamento string, fecha_nacimiento string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
LOCATION 's3://__RAW_BUCKET__/bronze/clientes/'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE EXTERNAL TABLE IF NOT EXISTS __DB_BRONZE__.polizas (
  id_poliza string, id_cliente string, producto string, fecha_inicio string,
  fecha_fin string, prima_anual string, estado string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
LOCATION 's3://__RAW_BUCKET__/bronze/polizas/'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE EXTERNAL TABLE IF NOT EXISTS __DB_BRONZE__.pagos_primas (
  id_pago string, id_poliza string, fecha_pago string, monto string, medio_pago string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
LOCATION 's3://__RAW_BUCKET__/bronze/pagos_primas/'
TBLPROPERTIES ('skip.header.line.count'='1');

CREATE EXTERNAL TABLE IF NOT EXISTS __DB_BRONZE__.siniestros (
  id_siniestro string, id_poliza string, fecha_siniestro string, fecha_reporte string,
  causa string, monto_reclamado string, monto_pagado string, estado string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
LOCATION 's3://__RAW_BUCKET__/bronze/siniestros/'
TBLPROPERTIES ('skip.header.line.count'='1');
