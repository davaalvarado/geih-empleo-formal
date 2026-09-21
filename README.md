# geih-empleo-formal

**Evaluación de impacto de la Jornada Única Escolar (JUE) sobre el empleo de las madres en Colombia**, desarrollada en la Especialización en Econometría de la Universidad Externado de Colombia (2026). Diseño de diferencias en diferencias escalonado (*staggered DiD*) con el estimador de Callaway-Sant'Anna, implementado en R.

> El repositorio se llama `geih-empleo-formal` porque la **GEIH** del DANE es la fuente de las variables de resultado del estudio: participación laboral, informalidad, horas trabajadas e ingresos de las madres.

---

## Pregunta de investigación

**¿Qué efecto tuvo la expansión de la Jornada Única Escolar sobre la participación laboral y la calidad del empleo de las madres con hijos en edad escolar en Colombia?**

Colombia implementa desde 2015 la Jornada Única Escolar, que extiende el horario de los colegios públicos de unas 4 horas diarias a 6–7 horas. El objetivo declarado de la política es educativo: mejorar los aprendizajes. Pero tiene una consecuencia no evaluada: **libera horas de cuidado en los hogares**.

La literatura existente sobre la JUE se ha concentrado casi por completo en el rendimiento académico (pruebas Saber 11°). Nadie ha medido de forma sistemática qué le pasó al empleo, a los ingresos y a la informalidad de las madres de esos estudiantes. Ese es el vacío que aborda este trabajo.

**Hipótesis:** la extensión de la jornada escolar reduce la carga de cuidado no remunerado de las madres y les permite aumentar su participación laboral y acceder a empleos de mejor calidad (menos informales, más horas, mayores ingresos).

---

## Datos

| Fuente | Entidad | Qué aporta al estudio | Dónde se descarga |
|---|---|---|---|
| **Educación Formal** | DANE (origen: SIMAT del MEN) | **Tratamiento:** matrícula por sede, municipio, año y jornada. Permite calcular qué proporción de la matrícula oficial de cada municipio está en jornada única | `microdatos.dane.gov.co` → EDU-MICRODATOS → "Educación Formal", un catálogo por año |
| **GEIH** | DANE | **Resultados:** participación laboral, formalidad/informalidad, horas trabajadas, ingresos y composición del hogar. Mensual | `microdatos.dane.gov.co` |
| **ENUT** | DANE | **Mecanismo:** horas de trabajo no remunerado y cuidado de menores. Solo cuatro levantamientos (2012–13, 2016–17, 2020–21, 2024–25) | `microdatos.dane.gov.co` |
| **C600 / Educación Formal** | DANE–MEN | Características de los establecimientos educativos | `microdatos.dane.gov.co` |

**Sobre la fuente del tratamiento.** El SIMAT es el sistema de matrícula del Ministerio de Educación, pero los datos que consume este proyecto llegan por la operación estadística **Educación Formal del DANE**, que publica la matrícula **ya agregada por sede y jornada** en lugar de registro por estudiante. Para calcular cobertura municipal esa presentación es más liviana y directa. Cada año tiene su propio catálogo en el portal (por ejemplo, 2018 corresponde al catálogo 615 y 2023 al 834).

**Período de análisis:** 2012–2023. Los años 2012–2014 son período pre-tratamiento limpio (la JUE no existía) y sirven para verificar tendencias paralelas; 2015 es el año de la Ley 1753 que crea la política; de ahí en adelante se mide la expansión y sus efectos.

Los microdatos **no se versionan en este repositorio** (son archivos pesados y públicos). El `.gitignore` excluye `datos/` y `salidas/` junto con los archivos temporales de RStudio.

---

## Método

### Diseño

**DiD escalonado.** Los municipios no adoptaron la Jornada Única todos al mismo tiempo: unos entraron en 2016, otros en 2018, otros más tarde. Esa variación en el *momento* de adopción es lo que identifica el efecto.

### Estimador

**Callaway y Sant'Anna (2021)**, paquete [`did`](https://bcallaway11.github.io/did/) de R.

El DiD tradicional de efectos fijos de dos vías (TWFE) está sesgado en diseños escalonados: usa a las unidades ya tratadas como control de las que se tratan después, y con efectos heterogéneos en el tiempo eso puede producir estimaciones con el signo equivocado. Callaway-Sant'Anna estima efectos por cohorte y período —los ATT(g,t)— y luego los agrega con ponderaciones explícitas, evitando ese problema.

**Robustez:** TWFE tradicional (`fixest`) y Sun-Abraham (`did2s`) como comparación.

### Unidades y variables

- **Nivel de tratamiento:** municipio (con agregación alternativa a departamento).
- **Unidad de análisis de los resultados:** mujeres de 18 a 55 años con al menos un hijo de 6 a 17 años en el hogar, identificadas en la GEIH mediante la variable de parentesco.
- **Variable de tratamiento:** porcentaje de matrícula oficial en jornada única por municipio y año (`cobertura_ju`). La jornada única se identifica por el **código 6** en la variable de jornada.
- **Año de adopción (`gname`):** primer año en que el municipio supera un umbral de cobertura. En el código el umbral está fijado en **5%**; los municipios que nunca lo superan quedan marcados con `gname = 0` (grupo de control, "nunca tratados"), como exige el paquete `did`. El umbral es una decisión metodológica y debe someterse a prueba de robustez con valores alternativos.
- **Variables de resultado (GEIH):** participación laboral (binaria), informalidad (binaria, condicional a estar ocupada), horas semanales de trabajo remunerado e ingreso laboral mensual.

### Supuestos de identificación

1. **Tendencias paralelas.** Se verifica estimando efectos dinámicos en los períodos previos a la adopción: la ausencia de efectos pre-tratamiento significativos funciona como prueba placebo temporal.
2. **No interferencia (SUTVA).** Se examina si la implementación en un municipio afecta a sus vecinos (spillovers espaciales).
3. **Ausencia de selección endógena.** Se revisa si la adopción temprana está correlacionada con características municipales previas —desarrollo económico, capacidad fiscal, demografía— que también podrían afectar el empleo femenino.

---

## Estructura del repositorio

```
geih-empleo-formal/
├── setup.R                 # instalación de paquetes (ejecutar una vez)
├── Codigo_Evaluacion.R     # Paso 2: variable de tratamiento
├── README.md
├── .gitignore
├── datos/
│   └── simat/              ← archivos anuales de Educación Formal (no versionados)
└── salidas/                ← .rds generados por el script (no versionados)
```

Las rutas se resuelven con el paquete [`here`](https://here.r-lib.org/), que ancla todo a la raíz del proyecto. **No hay rutas absolutas que editar**: el script funciona igual en cualquier máquina siempre que se respete esta estructura.

---

## Qué hay en cada archivo

### `setup.R`

Instala los paquetes del proyecto. Solo instala los que falten, así que puede ejecutarse sin riesgo de reinstalar lo que ya está.

### `Codigo_Evaluacion.R`

Construcción de la **variable de tratamiento** a partir de Educación Formal. Es el Paso 2 del proyecto y produce los insumos que alimentan la estimación. Va en cuatro bloques:

**1. Rutas y parámetros.** Resuelve las rutas con `here()`, crea `salidas/` si no existe y falla con un mensaje explícito si no encuentra los datos. Define el umbral de adopción.

**2. Lectura y construcción del panel municipal**

- `leer_archivo()` — lee indistintamente `.dta`, `.txt` y `.csv`, porque el formato cambia entre años, y normaliza los nombres de columna con `janitor::clean_names()`.
- `construir_tratamiento()` — detecta la columna de matrícula (que también cambia de nombre entre años: `sedealum_cantidad` en unos, la suma de hombres y mujeres en otros), extrae el código de municipio del código de sede, e identifica la jornada única por su código 6. Agrupa por municipio **y año**, y calcula `cobertura_ju = 100 × matrícula en jornada única / matrícula total`.
- Un bucle recorre todos los archivos de `datos/simat/` con `tryCatch()`, de modo que un archivo con estructura inesperada avisa del error sin abortar el proceso completo.

**3. Definición de cohortes de adopción.** Aplica el umbral del 5% para calcular el primer año de adopción de cada municipio y crea `gname` en el formato que espera el paquete `did`. Imprime la distribución de cohortes, que es literalmente la estructura del experimento natural.

**4. Agregación departamental.** Repite la lógica a nivel de departamento (`cod_dpto`, los dos primeros dígitos del código municipal), filtrando códigos inválidos. Produce una especificación alternativa, útil si el nivel municipal resulta demasiado ruidoso.

**Salidas:** `salidas/tratamiento_panel.rds` (municipio-año) y `salidas/tratamiento_depto.rds` (departamento-año).

### `.gitignore`

Plantilla estándar de R. Excluye `.Rhistory`, `.RData`, `.Rproj.user/` y demás archivos de sesión de RStudio, además de `datos/` y `salidas/`.

---

## Cómo reproducir

**Requisitos:** R (≥ 4.1, por el uso del pipe nativo `|>`) y RStudio.

1. **Clonar el repositorio** y abrir el archivo `.Rproj` en RStudio.
2. **Instalar los paquetes:** ejecutar `setup.R` una sola vez.
3. **Descargar los datos.** Entrar a `microdatos.dane.gov.co`, sección EDU-MICRODATOS, y descargar **Educación Formal** para los años 2012–2023 (un catálogo por año). Dejar todos los archivos en `datos/simat/`.
4. **Ejecutar `Codigo_Evaluacion.R`.** Genera los `.rds` en `salidas/`.

No hay que editar rutas en el código. Si el script se detiene, el mensaje indica qué falta.

---

## Avance del repositorio

La evaluación se estimó en el marco de la especialización. Este repositorio es su versión documentada y reproducible, que se publica paso a paso: las casillas marcadas indican los pasos cuyo código ya está disponible aquí.

- [x] **Paso 1** — Configuración del entorno en R
- [x] **Paso 2** — Variable de tratamiento desde Educación Formal: panel municipio-año, cohortes de adopción y grupo de control definidos
- [ ] **Paso 3** — Descarga y unión de módulos de la GEIH
- [ ] **Paso 4** — Identificación de madres con hijos en edad escolar y construcción de variables de resultado
- [ ] **Paso 5** — Panel municipio-año con resultados
- [ ] **Paso 6** — Estimación Callaway-Sant'Anna
- [ ] **Paso 7** — Efectos dinámicos, gráficos y tablas
- [ ] **Paso 8** — Canal de cuidado con la ENUT

---

## Limitaciones conocidas

- **Error de medición en el tratamiento.** La cobertura municipal de JUE es una aproximación a la exposición real de cada hogar: no se observa si los hijos de una madre concreta asistían a una sede con jornada única.
- **Cohortes tardías.** Las cohortes de adopción de 2021 y 2022 son pequeñas y coinciden con el período pos-pandemia, así que sus estimaciones son más ruidosas y conviene examinarlas por separado.
- **Umbral de adopción.** El 5% es un punto medio defendible, no un valor derivado de la teoría. Requiere prueba de robustez.
- **La ENUT no es continua**, así que el análisis del mecanismo de cuidado es más grueso que el de empleo.

---

## Autor

David Alvarado — [@davaalvarado](https://github.com/davaalvarado)

Economista (Universidad de la Salle) y Especialista en Econometría (Universidad Externado de Colombia).
