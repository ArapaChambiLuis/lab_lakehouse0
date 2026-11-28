# Guía de labs

Cada lab tiene su guía en esta carpeta y se ejecuta con `./lab.sh <n>` desde la raíz del repo.

| Lab | Guía | Comando | Tiempo |
|---|---|---|---|
| 0 · Setup | [lab0-setup](lab0-setup/README.md) | `./lab.sh 0 --email tu@correo.com` | 10 min |
| 1 · Bronze | [lab1-bronze](lab1-bronze/README.md) | `./lab.sh 1` | 10 min |
| 2 · Silver | [lab2-silver](lab2-silver/README.md) | `./lab.sh 2` | 20 min |
| 3 · Gold | [lab3-gold](lab3-gold/README.md) | `./lab.sh 3` | 15 min |
| 4 · Auditoría | [lab4-auditoria](lab4-auditoria/README.md) | `./lab.sh 4` | 15 min |
| 5 · Gobierno | [lab5-gobierno](lab5-gobierno/README.md) | opcional, manual | 30 min |

**¿Quieres saltar a un lab?** Ponte al día con `./deploy.sh --hasta <etapa>`:

| Para empezar en... | Ejecuta |
|---|---|
| Lab 2 | `./deploy.sh --hasta bronze` |
| Lab 3 | `./deploy.sh --hasta silver` |
| Lab 4 | `./deploy.sh --hasta gold` |

**¿Vas por la consola?** Sigue el [manual por consola](manual-consola/README.md). Para combinar consola y scripts: [consola y scripts](consola-y-scripts.md).

**Cada guía sigue el mismo formato:** 🎯 objetivo → ▶️ ejecutar → 🔍 qué pasó por detrás → ✅ verificar en la consola → 💬 para pensar.
