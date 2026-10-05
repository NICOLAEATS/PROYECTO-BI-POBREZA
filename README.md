# PROYECTO-BI-POBREZA — Pobreza monetaria Perú (ENAHO 2017-2025 + BID)

Catálogo público de datos del proyecto BI (UAC · Inteligencia de Negocios).

- **Página (GitHub Pages):** activa en Settings > Pages > Deploy from branch `main` + `/docs`. URL: `https://NICOLAEATS.github.io/PROYECTO-BI-POBREZA/`
- **Datos:** `docs/data/` (tasa.csv, bid.csv, comparativo.csv) + gráficos en `docs/assets/`
- **Base analítica (privada):** Neon Postgres `silent-feather-68150711` (593 MB, 310,838 hogares). Ver `modelo_estrella_pobreza.sql`, `etl_enaho_bid.py`, `neon_acceso_lectura.sql`.
- **Docs:** `Documentacion_Data_BI_Pobreza.docx`

Tasa oficial = `SUM(factor07*mieperho si pobre)/SUM(factor07*mieperho)`. 2024: 27.58% (INEI).
