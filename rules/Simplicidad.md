# Simplicidad

Resolvé el problema que existe hoy, no el que podría existir.

- **Sin abstracción especulativa.** Nada de interfaces, factories, strategies,
  registries o capas genéricas con una sola implementación. Se abstrae recién
  con el segundo o tercer caso real.
- **Sin configuración que nadie pidió.** Si un valor no varía hoy, es una
  constante, no un parámetro, flag o env var.
- **Sin manejo de errores para casos imposibles.** Validá en los bordes
  (input de usuario, red, DB); adentro confiá en los tipos.
- **El diff más chico que resuelve el problema.** No refactorices código
  vecino, no agregues helpers "por si acaso", no generalices una función
  para un solo caller.
- **Reusá antes de crear.** Buscá si ya existe algo que lo haga.
- **Si la solución te parece grande, decilo antes de escribirla.** Proponé
  la versión simple y mencioná la compleja como alternativa, no al revés.

Simple no es ingenuo: los casos borde reales, los tests y la seguridad
no se recortan. Lo que se recorta es lo hipotético.

Esto es sobre la **implementación**, no el **alcance**: una feature puede
ser rica en lo que hace y aun así usar la menor maquinaria posible para hacerlo.
