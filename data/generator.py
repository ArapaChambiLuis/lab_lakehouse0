#!/usr/bin/env python3
"""
Generador de datos sinteticos de "Aseguradora Andina S.A." (ficticia).

Solo usa la libreria estandar de Python: no hace falta pip install.
Los datos traen "suciedad" a proposito (duplicados, nulos, mayusculas
inconsistentes, montos negativos y polizas huerfanas) para que la capa
Silver tenga trabajo real que hacer.

Uso:
    python3 data/generator.py            # escribe en data/sample/
    python3 data/generator.py --out /tmp/datos --seed 7
"""
import argparse
import csv
import os
import random
from datetime import date, timedelta

NOMBRES = ["Luis", "Ana", "Carlos", "Maria", "Jorge", "Rosa", "Pedro", "Lucia",
           "Miguel", "Carmen", "Jose", "Elena", "Diego", "Sofia", "Raul", "Paola",
           "Victor", "Gabriela", "Hector", "Valeria"]
APELLIDOS = ["Quispe", "Flores", "Rojas", "Garcia", "Mamani", "Torres", "Chavez",
             "Ramos", "Vargas", "Castillo", "Huaman", "Mendoza", "Salazar", "Rios",
             "Cruz", "Paredes", "Gutierrez", "Arapa", "Condori", "Silva"]
DEPARTAMENTOS = ["LIMA", "AREQUIPA", "CUSCO", "PIURA", "LA LIBERTAD", "JUNIN",
                 "LAMBAYEQUE", "PUNO", "ICA", "LORETO"]
# producto: (prima anual minima, prima anual maxima, probabilidad de siniestro)
PRODUCTOS = {
    "AUTO": (900, 4500, 0.45),
    "SOAT": (90, 250, 0.30),
    "SALUD": (1200, 9000, 0.60),
    "VIDA": (600, 5000, 0.05),
    "HOGAR": (300, 1800, 0.15),
}
CAUSAS = {
    "AUTO": ["CHOQUE", "ROBO", "DANO_TERCEROS", "INCENDIO"],
    "SOAT": ["ACCIDENTE_TRANSITO"],
    "SALUD": ["HOSPITALIZACION", "CIRUGIA", "EMERGENCIA", "CONSULTA"],
    "VIDA": ["FALLECIMIENTO", "INVALIDEZ"],
    "HOGAR": ["INCENDIO", "ROBO", "INUNDACION", "SISMO"],
}
ESTADOS_SINIESTRO = ["PAGADO", "EN_EVALUACION", "RECHAZADO", "PAGADO", "PAGADO"]
MEDIOS_PAGO = ["TARJETA", "DEBITO_AUTOMATICO", "TRANSFERENCIA", "VENTANILLA"]

INICIO = date(2023, 1, 1)
FIN = date(2025, 12, 31)


def fecha_entre(rng, desde, hasta):
    dias = (hasta - desde).days
    return desde + timedelta(days=rng.randint(0, max(dias, 0)))


def ensuciar_texto(rng, valor):
    """Devuelve el texto con mayusculas/espacios inconsistentes a veces."""
    r = rng.random()
    if r < 0.05:
        return valor.lower()
    if r < 0.08:
        return "  " + valor.title() + " "
    return valor


def generar(out_dir, seed, n_clientes, n_polizas):
    rng = random.Random(seed)
    os.makedirs(out_dir, exist_ok=True)

    # ---------------- clientes (contiene PII) ----------------
    clientes = []
    for i in range(1, n_clientes + 1):
        nombre = rng.choice(NOMBRES)
        apellido = rng.choice(APELLIDOS)
        clientes.append({
            "id_cliente": f"CLI-{i:05d}",
            "dni": f"{rng.randint(10000000, 79999999)}",
            "nombre": f"{nombre} {apellido}",
            "email": f"{nombre}.{apellido}{i}@correo-ficticio.pe".upper()
                     if rng.random() < 0.1 else f"{nombre}.{apellido}{i}@correo-ficticio.pe".lower(),
            "departamento": ensuciar_texto(rng, rng.choice(DEPARTAMENTOS)),
            "fecha_nacimiento": fecha_entre(rng, date(1950, 1, 1), date(2005, 12, 31)).isoformat(),
        })
    # duplicados exactos (error tipico de extraccion)
    clientes += rng.sample(clientes, k=max(1, n_clientes // 50))

    # ---------------- polizas ----------------
    polizas = []
    for i in range(1, n_polizas + 1):
        producto = rng.choice(list(PRODUCTOS))
        pmin, pmax, _ = PRODUCTOS[producto]
        inicio = fecha_entre(rng, INICIO, date(2025, 6, 30))
        polizas.append({
            "id_poliza": f"POL-{i:06d}",
            "id_cliente": f"CLI-{rng.randint(1, n_clientes):05d}",
            "producto": ensuciar_texto(rng, producto),
            "fecha_inicio": inicio.isoformat(),
            "fecha_fin": (inicio + timedelta(days=365)).isoformat(),
            "prima_anual": f"{rng.uniform(pmin, pmax):.2f}",
            "estado": rng.choice(["VIGENTE", "VIGENTE", "VIGENTE", "ANULADA", "VENCIDA"]),
        })
    # polizas huerfanas: apuntan a un cliente que no existe
    for j in range(5):
        p = dict(rng.choice(polizas))
        p["id_poliza"] = f"POL-9{j:05d}"
        p["id_cliente"] = "CLI-99999"
        polizas.append(p)

    # ---------------- pagos de primas (mensuales) ----------------
    pagos = []
    n_pago = 1
    for p in polizas:
        if p["estado"] == "ANULADA" and rng.random() < 0.5:
            continue
        inicio = date.fromisoformat(p["fecha_inicio"])
        cuota = float(p["prima_anual"]) / 12
        for m in range(12):
            fecha = inicio + timedelta(days=30 * m)
            if fecha > FIN:
                break
            if rng.random() < 0.06:  # cuota impaga
                continue
            pagos.append({
                "id_pago": f"PAG-{n_pago:07d}",
                "id_poliza": p["id_poliza"],
                "fecha_pago": fecha.isoformat(),
                "monto": f"{cuota:.2f}",
                "medio_pago": rng.choice(MEDIOS_PAGO),
            })
            n_pago += 1

    # ---------------- siniestros ----------------
    siniestros = []
    n_sin = 1
    for p in polizas:
        producto = p["producto"].strip().upper()
        _, _, prob = PRODUCTOS[producto]
        if rng.random() > prob:
            continue
        for _ in range(rng.choice([1, 1, 1, 2])):
            inicio = date.fromisoformat(p["fecha_inicio"])
            fecha_sin = fecha_entre(rng, inicio, min(inicio + timedelta(days=364), FIN))
            prima = float(p["prima_anual"])
            reclamado = round(rng.uniform(0.2, 3.0) * prima, 2)
            estado = rng.choice(ESTADOS_SINIESTRO)
            pagado = round(reclamado * rng.uniform(0.6, 1.0), 2) if estado == "PAGADO" else 0.0
            siniestros.append({
                "id_siniestro": f"SIN-{n_sin:05d}",
                "id_poliza": p["id_poliza"],
                "fecha_siniestro": fecha_sin.isoformat(),
                "fecha_reporte": (fecha_sin + timedelta(days=rng.randint(0, 20))).isoformat(),
                "causa": rng.choice(CAUSAS[producto]),
                "monto_reclamado": f"{reclamado:.2f}",
                "monto_pagado": f"{pagado:.2f}",
                "estado": ensuciar_texto(rng, estado),
            })
            n_sin += 1

    # SIN-00042 es el protagonista del Lab 4 (time travel): siempre PAGADO y con monto.
    for s in siniestros:
        if s["id_siniestro"] == "SIN-00042":
            s["estado"] = "PAGADO"
            s["monto_reclamado"] = "18500.00"
            s["monto_pagado"] = "17250.00"
            s["causa"] = "ROBO"

    # suciedad: montos nulos y negativos
    for s in rng.sample(siniestros, k=max(1, len(siniestros) // 40)):
        if s["id_siniestro"] != "SIN-00042":
            s["monto_reclamado"] = ""
    for s in rng.sample(siniestros, k=max(1, len(siniestros) // 80)):
        if s["id_siniestro"] != "SIN-00042":
            s["monto_pagado"] = "-" + s["monto_pagado"]
    # suciedad: el mismo siniestro reenviado con fecha_reporte posterior
    reenvios = []
    for s in rng.sample(siniestros, k=max(1, len(siniestros) // 30)):
        r = dict(s)
        r["fecha_reporte"] = (date.fromisoformat(s["fecha_reporte"]) + timedelta(days=3)).isoformat()
        reenvios.append(r)
    siniestros += reenvios

    tablas = {
        "clientes": clientes,
        "polizas": polizas,
        "pagos_primas": pagos,
        "siniestros": siniestros,
    }
    for nombre, filas in tablas.items():
        rng.shuffle(filas)
        ruta = os.path.join(out_dir, f"{nombre}.csv")
        with open(ruta, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(filas[0].keys()))
            w.writeheader()
            w.writerows(filas)
        print(f"  {nombre:<13} {len(filas):>6} filas -> {ruta}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    base = os.path.dirname(os.path.abspath(__file__))
    parser.add_argument("--out", default=os.path.join(base, "sample"))
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--clientes", type=int, default=2000)
    parser.add_argument("--polizas", type=int, default=3000)
    args = parser.parse_args()
    print("Generando datos sinteticos de Aseguradora Andina S.A.")
    generar(args.out, args.seed, args.clientes, args.polizas)


if __name__ == "__main__":
    main()
