# 2026-10-03 — ¿Por qué salen 34 departamentos y códigos con punto?
# Hallazgo: los códigos con punto eran notación científica: el .dta de 2019 trae sede_codigo
#           como número. El 83 no existe en la DIVIPOLA; son sedes que la carátula ubica en
#           Caquetá y no duplican a las registradas bajo el 18.
# Decisión: se corrigió la extracción en Codigo_Evaluacion.R (commit 9be1e4a). El 83 se resolvió
#           después con la carátula (commit d31df92; ver 2026-10-07_alcance_caratula.R).
# Nota:     estas consultas se corrieron sobre el panel que producía el script antes del commit
#           9be1e4a. Con el script actual ya no devuelven lo mismo; se conservan como registro
#           de por qué se tomó cada decisión.

library(tidyverse)
library(here)

tratamiento_panel <- readRDS(here("salidas", "tratamiento_panel.rds"))
tratamiento_depto <- readRDS(here("salidas", "tratamiento_depto.rds"))

# 1. ¿Cuáles son los 34 departamentos? Los 33 válidos más el 83.
tratamiento_depto |> distinct(cod_dpto) |> arrange(cod_dpto) |> pull() |> print()

# 2. ¿Todos los códigos de municipio tienen 5 caracteres? ¿En cuántos años aparece cada uno?
table(nchar(tratamiento_panel$cod_mpio)) |> print()
tratamiento_panel |> count(cod_mpio, name = "anios") |> count(anios) |> print()

# 3. Códigos con departamento inválido. Salen dos familias: la del 83, presente los siete
#    años, y la de los códigos que empiezan con punto, presente en un solo año.
dptos_validos <- c("05","08","11","13","15","17","18","19","20","23","25","27",
                   "41","44","47","50","52","54","63","66","68","70","73","76",
                   "81","85","86","88","91","94","95","97","99")

tratamiento_panel |>
  mutate(cod_dpto = substr(cod_mpio, 1, 2)) |>
  filter(!cod_dpto %in% dptos_validos) |>
  group_by(cod_mpio) |>
  summarise(anios = n(),
            matricula_media = round(mean(matricula_total)),
            .groups = "drop") |>
  arrange(desc(matricula_media)) |>
  print(n = 50)

# 4. Los códigos con punto están todos en 2019: es el archivo que trae sede_codigo como número.
tratamiento_panel |> filter(substr(cod_mpio, 1, 1) == ".") |> count(anio) |> print()

# 5. ¿El 83 duplica al 18 o lo complementa? Las matrículas son distintas: son sedes diferentes.
tratamiento_panel |>
  filter(cod_mpio %in% c("18001", "83001", "18247", "83247", "18765", "83765")) |>
  arrange(cod_mpio, anio) |>
  select(cod_mpio, anio, matricula_total, matricula_unica, cobertura_ju) |>
  print(n = 50)

# 6. Caquetá bajo el 18: aparecen sus 16 municipios y un 18765 que no existe en la DIVIPOLA.
tratamiento_panel |>
  filter(substr(cod_mpio, 1, 2) == "18") |>
  distinct(cod_mpio) |> pull() |> print()

# 7. El archivo crudo de 2014: los códigos de sede tienen 12 caracteres y el 83 viene en el
#    dato. No trae columnas con el nombre del municipio ni del departamento.
d  <- haven::read_dta(here("datos", "simat", "2014_alumnos_por_jornada.dta")) |>
  janitor::clean_names()
cc <- as.character(d$sede_codigo)

table(nchar(cc)) |> print()
unique(cc[substr(cc, 2, 3) == "83"])    |> head(10) |> print()
unique(cc[substr(cc, 2, 6) == "18001"]) |> head(5)  |> print()
names(d) |> print()

# 8. La cobertura llega a 100 en municipios pequeños, casi todos de Boyacá. No es un error.
summary(tratamiento_panel$cobertura_ju) |> print()

tratamiento_panel |>
  filter(cobertura_ju == 100) |>
  select(cod_mpio, anio, matricula_total) |>
  arrange(desc(matricula_total)) |>
  print(n = 30)
