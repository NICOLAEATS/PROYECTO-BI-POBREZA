"""
ETL BI Pobreza - ENAHO Sumaria (2017-2025) + BID -> Postgres nube (Neon/Supabase)
Uso:
  pip install pandas sqlalchemy psycopg2-binary
  py etl_enaho_bid.py --enaho "C:/Users/Nouch/Desktop/uac/BI/966-Modulo34.zip" --bid_dir ./bid --db "postgresql://user:pass@ep-xxx.neon.tech:5432/pobreza?sslmode=require"
Genera también CSVs listos para COPY si no hay conexión: --only-csv
"""
import argparse, zipfile, io, sys
from pathlib import Path
import pandas as pd

# Columnas BI mínimas (de 163) para no saturar free-tier 500MB/3GB
COLS_ENAHO = ["AÑO","MES","CONGLOME","VIVIENDA","HOGAR","UBIGEO","DOMINIO","ESTRATO",
  "MIEPERHO","TOTMIEHO","PERCEPHO","INGHOG1D","INGHOG2D","GASHOG1D","GASHOG2D",
  "INGMO1HD","INGMO2HD","ESTRSOCIAL","LD","LINPE","LINEA","POBREZA","FACTOR07",
  "LINEAV","POBREZAV"]

RENAME = {"AÑO":"anio","MES":"mes","CONGLOME":"conglome","VIVIENDA":"vivienda",
  "HOGAR":"hogar","UBIGEO":"ubigeo","DOMINIO":"dominio_id","ESTRATO":"estrato_id",
  "MIEPERHO":"mieperho","TOTMIEHO":"totmieho","PERCEPHO":"percepho",
  "INGHOG1D":"inghog1d","INGHOG2D":"inghog2d","GASHOG1D":"gashog1d","GASHOG2D":"gashog2d",
  "INGMO1HD":"ingmo1hd","INGMO2HD":"ingmo2hd","ESTRSOCIAL":"estrsocial",
  "LD":"ld","LINPE":"linpe","LINEA":"linea","POBREZA":"pobreza_id",
  "FACTOR07":"factor07","LINEAV":"lineav","POBREZAV":"pobrezav"}

def load_sumaria_csv(path_or_zip: str, inner_name: str = None) -> pd.DataFrame:
    """Lee Sumaria-AAAA.csv con encoding latin1 (tildes INEI). Acepta .csv o .zip."""
    p = Path(path_or_zip)
    if p.suffix.lower() == ".zip":
        z = zipfile.ZipFile(p)
        # Si no se indica inner, tomar el primer Sumaria-*.csv que NO sea 12g (coma, no ;)
        cands = [n for n in z.namelist() if n.endswith(".csv") and "Sumaria" in n and "12g" not in n]
        if not cands:
            cands = [n for n in z.namelist() if n.endswith(".csv")]
        target = inner_name or sorted(cands)[0]
        print(f"[ENAHO] leyendo dentro del zip: {target}")
        raw = z.read(target)
        # ENAHO usa coma como separador en Sumaria-AAAA.csv y ; en 12g
        sep = ";" if "12g" in target else ","
        df = pd.read_csv(io.BytesIO(raw), encoding="latin1", sep=sep, low_memory=False)
    else:
        df = pd.read_csv(p, encoding="latin1", low_memory=False)
    # Normalizar nombre AÑO (viene como A�O si se leyó utf-8)
    df.columns = [c.strip() for c in df.columns.astype(str)]
    ano_col = [c for c in df.columns if c.startswith("A")]
    # Mapeo robusto: buscar columna que empiece con 'A' y termine con 'O'
    for c in list(df.columns):
        if c in ("A�O","AÃ‘O","ANO") :
            df = df.rename(columns={c:"AÑO"})
    missing = [c for c in COLS_ENAHO if c not in df.columns]
    if missing:
        print(f"[WARN] columnas faltantes: {missing}", file=sys.stderr)
    keep = [c for c in COLS_ENAHO if c in df.columns]
    df = df[keep].rename(columns={k:v for k,v in RENAME.items() if k in keep})
    # Tipos y limpieza
    df["ubigeo"] = df["ubigeo"].astype(str).str.zfill(6)
    df["anio"] = pd.to_numeric(df["anio"], errors="coerce").astype("Int16")
    for c in ["dominio_id","estrato_id","pobreza_id","mes"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce").astype("Int16")
    # Validaciones de calidad (según documento Unidad 1)
    assert df["pobreza_id"].isin([1,2,3]).all(), "POBREZA fuera de {1,2,3}"
    assert (df["factor07"] > 0).all(), "FACTOR07 debe ser >0"
    assert df[["anio","conglome","vivienda","hogar"]].notna().all().all(), "PK con nulos"
    assert not df.duplicated(subset=["anio","conglome","vivienda","hogar"]).any(), "Duplicados en PK hogar"
    print(f"[ENAHO] filas={len(df)} años={sorted(df['anio'].dropna().unique().tolist())}")
    # Tasa ponderada de control (debe coincidir con INEI ~27-30% 2024)
    tasa = (df.loc[df["pobreza_id"].isin([1,2]),"factor07"].sum() / df["factor07"].sum())
    print(f"[ENAHO] tasa pobreza ponderada muestra: {tasa:.4f}")
    return df

def load_bid(csv_path: str) -> pd.DataFrame:
    """Filtra BID a grano pais+anio+area (Total demográfico) para evitar duplicados."""
    df = pd.read_csv(csv_path, low_memory=False)
    # Aislar nivel Total en variables demográficas (hallazgo calidad del informe)
    for col in ["quintile","sex","education_level","age","ethnicity"]:
        if col in df.columns:
            df = df[df[col].astype(str) == "Total"]
    keep = ["isoalpha3","year","area","indicator","value","se","cv","sample","source"]
    keep = [c for c in keep if c in df.columns]
    df = df[keep].rename(columns={"year":"anio"})
    df["area"] = df["area"].replace({"Total":"Total","urban":"urban","rural":"rural"})
    # value debe estar 0-1 (si viene 0-100 dividir)
    if (df["value"] > 1.5).any():
        print("[BID] detectada escala 0-100, convirtiendo a 0-1")
        df["value"] = df["value"] / 100.0
    print(f"[BID] filas filtradas={len(df)} países={df['isoalpha3'].nunique()} años={df['anio'].min()}-{df['anio'].max()}")
    return df

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--enaho", required=True, help="zip o csv Sumaria (se puede repetir por año)")
    ap.add_argument("--enaho_list", nargs="*", default=[], help="CSVs adicionales 2017-2025")
    ap.add_argument("--bid", required=False, help="CSV BID poverty")
    ap.add_argument("--db", required=False, help="URL postgres Neon/Supabase")
    ap.add_argument("--only-csv", action="store_true", help="solo generar CSVs para COPY")
    ap.add_argument("--out", default="./out", help="carpeta salida")
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)

    frames = [load_sumaria_csv(a.enaho)]
    for extra in a.enaho_list:
        frames.append(load_sumaria_csv(extra))
    enaho = pd.concat(frames, ignore_index=True)
    enaho_path = out / "fact_2017_2025.csv"
    enaho.to_csv(enaho_path, index=False)
    print(f"[OUT] {enaho_path} ({enaho_path.stat().st_size/1e6:.2f} MB)")

    bid = None
    if a.bid:
        bid = load_bid(a.bid)
        bid_path = out / "bid_filtrado.csv"
        bid.to_csv(bid_path, index=False)
        print(f"[OUT] {bid_path}")

    if a.db and not a.only_csv:
        from sqlalchemy import create_engine
        eng = create_engine(a.db)
        with eng.begin() as c:
            years = sorted(set(enaho["anio"].dropna().astype(int).tolist()))
            if bid is not None:
                years += sorted(set(bid["anio"].dropna().astype(int).tolist()))
            for y in sorted(set(years)):
                c.exec_driver_sql("INSERT INTO dim_tiempo(anio) VALUES (%s) ON CONFLICT DO NOTHING", (y,))
            enaho.to_sql("stg_enaho", c, if_exists="replace", index=False)
            # Inserción ordenada evitando PK generada:
            c.exec_driver_sql("""
              INSERT INTO fact_hogar_pobreza(anio,mes,conglome,vivienda,hogar,ubigeo,dominio_id,estrato_id,
                mieperho,totmieho,percepho,inghog1d,inghog2d,gashog1d,gashog2d,ingmo1hd,ingmo2hd,
                estrsocial,ld,linpe,linea,pobreza_id,factor07,lineav,pobrezav)
              SELECT anio,mes,conglome,vivienda,hogar,ubigeo,dominio_id,estrato_id,
                mieperho,totmieho,percepho,inghog1d,inghog2d,gashog1d,gashog2d,ingmo1hd,ingmo2hd,
                estrsocial,ld,linpe,linea,pobreza_id,factor07,lineav,pobrezav FROM stg_enaho
              ON CONFLICT (anio,conglome,vivienda,hogar) DO NOTHING""")
            c.exec_driver_sql("DROP TABLE IF EXISTS stg_enaho")
            if bid is not None:
                bid[["isoalpha3"]].drop_duplicates().to_sql("stg_paises", c, if_exists="replace", index=False)
                c.exec_driver_sql("INSERT INTO dim_pais(isoalpha3,nombre) SELECT DISTINCT isoalpha3, isoalpha3 FROM stg_paises ON CONFLICT (isoalpha3) DO NOTHING")
                c.exec_driver_sql("DROP TABLE IF EXISTS stg_paises")
                bid.to_sql("stg_bid", c, if_exists="replace", index=False)
                c.exec_driver_sql("""
                  INSERT INTO fact_bid_pobreza(isoalpha3,anio,area,indicator,value,se,cv,sample,source)
                  SELECT isoalpha3,anio,area,indicator,value,se,cv,sample,source FROM stg_bid
                  ON CONFLICT (isoalpha3,anio,area,indicator) DO NOTHING""")
                c.exec_driver_sql("DROP TABLE IF EXISTS stg_bid")
        print("[DB] carga completa. Verifique con SELECT * FROM vw_tasa_pobreza_ponderada LIMIT 5;")

if __name__ == "__main__":
    main()
