# 2026-10-07 — ¿El desajuste entre sede_codigo y el municipio real es solo de Caquetá?
# Hallazgo: no. En la carátula de 2018, 3.040 de 58.860 sedes (5,2%) están en un municipio
#           distinto al que sale del código, en 32 de los 33 departamentos; 546 cambian de
#           departamento. La carátula trae una fila por sede y ningún municipio en blanco.
# Decisión: rehacer el paso 2 uniendo cada año de matrícula con su carátula por sede_codigo
#           y agrupando por codigointernomuni.

library(tidyverse)
library(here)

car <- haven::read_dta(here("datos", "simat_sedes", "2018_caratula_sede.dta")) |>
  janitor::clean_names() |>
  mutate(cod5 = substr(sede_codigo, 2, 6))

# A. ¿Una fila por sede? ¿El municipio viene completo?
car |>
  summarise(filas          = n(),
            sedes_unicas   = n_distinct(sede_codigo),
            muni_en_blanco = sum(is.na(codigointernomuni) | codigointernomuni == ""),
            muni_5_digitos = sum(nchar(codigointernomuni) == 5, na.rm = TRUE)) |>
  print()

# B. ¿Cuántas sedes tienen un municipio distinto al que sale del código?
car_ok <- car |> filter(!is.na(codigointernomuni), codigointernomuni != "")

car_ok |>
  summarise(coinciden       = sum(cod5 == codigointernomuni),
            difieren        = sum(cod5 != codigointernomuni),
            cambian_de_dpto = sum(substr(cod5, 1, 2) != codigointernodepto, na.rm = TRUE)) |>
  print()

# C. ¿En qué departamentos están las que difieren?
car_ok |>
  filter(cod5 != codigointernomuni) |>
  count(codigointernodepto, depto, sort = TRUE) |>
  print(n = 40)