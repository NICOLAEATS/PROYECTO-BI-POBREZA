import streamlit as st
import pandas as pd
from sqlalchemy import create_engine, text

st.set_page_config(page_title="bi probreza peru", layout="wide")
st.title("bi probreza peru")

TABLES = {
 "fact_hogar_pobreza (MART, 310k)": "fact_hogar_pobreza",
 "vw_tasa_pobreza_ponderada": "vw_tasa_pobreza_ponderada",
 "vw_comparativo_enaho_bid": "vw_comparativo_enaho_bid",
 "vw_bid_peru_serie": "vw_bid_peru_serie",
 "raw_sumaria_anual_2017": "raw_sumaria_anual_2017",
 "raw_sumaria_anual_2018": "raw_sumaria_anual_2018",
 "raw_sumaria_anual_2019": "raw_sumaria_anual_2019",
 "raw_sumaria_anual_2020": "raw_sumaria_anual_2020",
 "raw_sumaria_anual_2021": "raw_sumaria_anual_2021",
 "raw_sumaria_anual_2022": "raw_sumaria_anual_2022",
 "raw_sumaria_anual_2023": "raw_sumaria_anual_2023",
 "raw_sumaria_anual_2024 (163 cols)": "raw_sumaria_anual_2024",
 "raw_sumaria_anual_2025": "raw_sumaria_anual_2025",
 "raw_sumaria_12g_2024 (242 cols)": "raw_sumaria_12g_2024",
 "raw_bid_full (26k)": "raw_bid_full",
 "fact_bid_pobreza": "fact_bid_pobreza",
 "raw_pobreza_extrema_kaggle": "raw_pobreza_extrema_kaggle",
 "raw_pensiones_environment": "raw_pensiones_environment",
 "raw_pensiones_performance": "raw_pensiones_performance",
 "raw_pensiones_sustainability": "raw_pensiones_sustainability",
 "raw_pensiones_society": "raw_pensiones_society",
 "raw_pensiones_peru": "raw_pensiones_peru",
 "dim_departamento": "dim_departamento",
 "dim_dominio": "dim_dominio",
 "dim_condicion_pobreza": "dim_condicion_pobreza",
 "dim_tiempo": "dim_tiempo",
}

@st.cache_resource
def engine():
    cfg = st.secrets["neon"]
    url = f"postgresql+psycopg2://{cfg['user']}:{cfg['password']}@{cfg['host']}:{cfg.get('port',5432)}/{cfg['database']}?sslmode=require&channel_binding=require"
    return create_engine(url, pool_pre_ping=True)

def q(sql, params=None):
    with engine().connect() as c:
        return pd.read_sql(text(sql), c, params=params)

label = st.selectbox("Tabla", list(TABLES.keys()), index=0)
tbl = TABLES[label]
c1, c2, c3 = st.columns(3)
page = c1.number_input("Página", min_value=1, value=1, step=1)
per = c2.selectbox("Filas por página", [50, 100, 200], index=1)
anio = c3.text_input("Filtro año (ej 2024, vacío=todos)", "")
where, params = "", {}
if anio.strip() and tbl in ("fact_hogar_pobreza",) or (anio.strip() and "raw_sumaria_anual" in tbl):
    where = "WHERE anio = :a"; params = {"a": int(anio.strip())}
try:
    total = q(f'SELECT COUNT(*) AS n FROM "{tbl}" {where}', params).iloc[0]["n"]
    st.write(f"**{tbl}**: {int(total):,} filas · página {page} ({per} por página) · todo visible, nada escondido")
    df = q(f'SELECT * FROM "{tbl}" {where} LIMIT :l OFFSET :o', {**params, "l": int(per), "o": int((page-1)*int(per))})
    st.dataframe(df, use_container_width=True)
    st.download_button("Descargar esta página (CSV)", df.to_csv(index=False), f"{tbl}_p{page}.csv")
except Exception as e:
    st.error(f"No se pudo leer: {e}. Revisa los Secrets en Streamlit Cloud.")
