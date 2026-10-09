# Exploración — viernes 9 de octubre de 2026
#
# Pregunta: la GEIH publica resultados por departamento solo para 23 departamentos y Bogotá;
#   Arauca, Casanare, Putumayo, San Andrés, Amazonas, Guainía, Guaviare, Vaupés y Vichada solo
#   entran al total nacional. Si el panel departamental se limita a esas 24 unidades, ¿cómo quedan
#   las cohortes de adopción y queda algún departamento nunca tratado?
#
# Hallazgo: con el umbral de 5%, ninguno de los 24 departamentos que publica la GEIH queda nunca
#   tratado (el único de los 33 es Vaupés, que la GEIH no publica). Cohortes: 2016 -> 8,
#   2018 -> 12, 2019 -> 2 (Cauca y Nariño), 2021 -> 1 (Sucre) y 2022 -> 1 (Bolívar, que cruza con
#   5,03%). Con "aún no tratados", la cohorte 2018 se compara en 2018 contra 4 departamentos, en
#   2019 contra 2, en 2021 contra 1 y en 2022 contra ninguno; Bolívar no se puede estimar. Esos
#   controles ya tenían entre 1% y 5% de cobertura. El diseño depende mucho del umbral: con 7,5%
#   quedan 3 nunca tratados; con 10%, 5 (Bolívar, Cauca, Meta, Nariño y Sucre, con cobertura máxima
#   entre 5,03% y 8,24%); con 15%, 10, incluidos Bogotá, Antioquia y Valle (entre 11,3% y 12,3%).
#
# Decisión: el 5% sigue como especificación principal, porque se fijó en el código de junio,
#   antes de ver estos datos. El 10% se reporta como especificación de robustez. En la metodología
#   se declara que ningún umbral deja controles con cobertura cero y que los nunca tratados no son
#   un grupo al azar: son los que menos adoptaron.
#
# Nota: corre sobre salidas/tratamiento_depto.rds generado por Codigo_Evaluacion.R
#   del commit 4b395d7 (umbral de 5%, matrícula oficial y no oficial).

library(tidyverse)
library(here)

depto    <- readRDS(here("salidas", "tratamiento_depto.rds"))
divipola <- read_csv(here("referencias", "divipola_municipios.csv"),
                     col_types = cols(.default = "c")) |>
  janitor::clean_names()

# Departamentos que la GEIH no publica por separado:
# 81 Arauca, 85 Casanare, 86 Putumayo, 88 San Andrés, 91 Amazonas,
# 94 Guainía, 95 Guaviare, 97 Vaupés, 99 Vichada
fuera_geih <- c("81", "85", "86", "88", "91", "94", "95", "97", "99")

nombres <- divipola |> distinct(cod_dpto, dpto)

# A. Cohorte de cada departamento, marcando si la GEIH lo publica
cohortes <- depto |>
  distinct(cod_dpto, gname) |>
  left_join(nombres, by = "cod_dpto") |>
  mutate(en_geih = !cod_dpto %in% fuera_geih) |>
  arrange(gname, cod_dpto)

print(cohortes, n = 40)

# B. Cohortes entre los 24 que publica la GEIH
cohortes |>
  filter(en_geih) |>
  count(gname) |>
  print()

# C. Cobertura de jornada única por año en esos 24 (para ver qué tan lejos del umbral de 5% quedan)
depto |>
  filter(!cod_dpto %in% fuera_geih) |>
  left_join(nombres, by = "cod_dpto") |>
  select(cod_dpto, dpto, anio, cobertura_ju) |>
  pivot_wider(names_from = anio, values_from = cobertura_ju) |>
  arrange(cod_dpto) |>
  print(n = 30, width = Inf)

# D. Sensibilidad al umbral: cohortes de los 24 con umbrales de 5%, 7,5%, 10% y 15%
umbrales <- c(5, 7.5, 10, 15)

primer_cruce <- function(anio, cobertura, u) {
  cruza <- which(cobertura >= u)
  if (length(cruza) == 0) 0 else min(anio[cruza])
}

depto_geih <- depto |> filter(!cod_dpto %in% fuera_geih)

sensibilidad <- map_dfr(umbrales, function(u) {
  depto_geih |>
    group_by(cod_dpto) |>
    summarise(gname = primer_cruce(anio, cobertura_ju, u), .groups = "drop") |>
    mutate(umbral = u)
})

sensibilidad |>
  mutate(cohorte = if_else(gname == 0, "nunca", as.character(gname))) |>
  count(umbral, cohorte) |>
  pivot_wider(names_from = cohorte, values_from = n, values_fill = 0, names_sort = TRUE) |>
  print(width = Inf)

# E. Departamentos nunca tratados con cada umbral y su cobertura máxima en 2014-2022
sensibilidad |>
  filter(gname == 0) |>
  left_join(depto_geih |>
              group_by(cod_dpto) |>
              summarise(cobertura_maxima = max(cobertura_ju, na.rm = TRUE), .groups = "drop"),
            by = "cod_dpto") |>
  left_join(nombres, by = "cod_dpto") |>
  select(umbral, cod_dpto, dpto, cobertura_maxima) |>
  arrange(umbral, cod_dpto) |>
  print(n = 40)
