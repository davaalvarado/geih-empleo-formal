# 2026-10-07 — ¿Todos los municipios del panel existen en la DIVIPOLA? ¿Cuáles no están los siete años?
# Hallazgo: de los 1.121 códigos del panel, 1.120 existen en la DIVIPOLA (1.122 entradas). El que no
#           existe es el 94663, que la carátula llama MAPIRIPANA (Guainía): un área no municipalizada
#           que se integró al municipio de Barrancominas (94343) en diciembre de 2019.
#           No están los siete años: La Pedrera, La Victoria y Puerto Arica (Amazonas) y el 94663.
#           De paso: en 2018 la matrícula de Guainía cae a menos de la mitad (Inírida pasa de 7.486
#           en 2016 a 2.330 y vuelve a 8.280 en 2019). Queda por revisar si pasa en otros departamentos.
# Decisión: el 94663 se recodifica a 94343 con referencias/equivalencias_municipios.csv, y
#           Codigo_Evaluacion.R se detiene si aparece un código que no esté en la DIVIPOLA.
# Nota:     corrió sobre el panel del commit d31df92, antes de la tabla de equivalencias. Con el
#           script actual el 94663 ya no aparece en el panel.

library(tidyverse)
library(here)

# La DIVIPOLA se baja una sola vez y se guarda en referencias/, que sí se versiona,
# para que el panel se pueda reconstruir sin conexión.
# Fuente: datos.gov.co, conjunto DIVIPOLA de códigos de municipios (gdxc-w37w).
ruta_divipola <- here("referencias", "divipola_municipios.csv")

if (!file.exists(ruta_divipola)) {
  dir.create(here("referencias"), showWarnings = FALSE)
  readr::read_csv("https://www.datos.gov.co/resource/gdxc-w37w.csv?$limit=1500",
                  col_types = readr::cols(.default = "c")) |>
    readr::write_csv(ruta_divipola)
}

divipola <- readr::read_csv(ruta_divipola, col_types = readr::cols(.default = "c")) |>
  janitor::clean_names()

tratamiento_panel <- readRDS(here("salidas", "tratamiento_panel.rds"))
codigos_panel     <- tratamiento_panel |> distinct(cod_mpio)

# A. ¿Cómo viene la DIVIPOLA?
divipola |>
  summarise(filas            = n(),
            codigos_unicos   = n_distinct(cod_mpio),
            de_cinco_digitos = sum(str_detect(cod_mpio, "^[0-9]{5}$"), na.rm = TRUE),
            departamentos    = n_distinct(cod_dpto)) |>
  print()
divipola |> count(tipo_municipio) |> print()

# B. Códigos del panel que no existen en la DIVIPOLA
codigos_panel |>
  anti_join(divipola, by = "cod_mpio") |>
  print(n = 50)

# C. Municipios de la DIVIPOLA que no aparecen en el panel
divipola |>
  anti_join(codigos_panel, by = "cod_mpio") |>
  select(cod_mpio, nom_mpio, dpto, tipo_municipio) |>
  print(n = 50)

# D. Municipios del panel que no están en los siete años
tratamiento_panel |>
  group_by(cod_mpio) |>
  summarise(anios = n(), presentes = paste(anio, collapse = " "), .groups = "drop") |>
  filter(anios < 7) |>
  left_join(divipola |> select(cod_mpio, nom_mpio, dpto), by = "cod_mpio") |>
  print()


# E. ¿Qué es el 94663?
# Guainía en la DIVIPOLA vigente
divipola |>
  filter(cod_dpto == "94") |>
  select(cod_mpio, nom_mpio, tipo_municipio) |>
  print()

# Nombre que le da la carátula de 2014
haven::read_dta(here("datos", "simat_sedes", "2014_caratula_sede.dta")) |>
  janitor::clean_names() |>
  filter(codigointernomuni == "94663") |>
  count(codigointernomuni, muni, depto) |>
  print()

# Matrícula de cada código de Guainía, año por año
tratamiento_panel |>
  filter(substr(cod_mpio, 1, 2) == "94") |>
  select(cod_mpio, anio, matricula_total) |>
  pivot_wider(names_from = anio, values_from = matricula_total, names_sort = TRUE) |>
  print()