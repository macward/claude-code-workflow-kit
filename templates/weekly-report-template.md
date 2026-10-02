# Weekly Report Template

Plantilla para reportes semanales guardados en Meridian (carpeta `reports/`). Mismo público que `recap-template.md`: todo el equipo, sin jerga técnica. Sirve tanto para un solo proyecto como para varios combinados en un mismo reporte — la sección "Por proyecto" se repite una vez por proyecto y funciona igual con uno solo.

---

## Authoring rules

1. **Sin tecnicismos sin explicación.** No "refactor", "PR", "async", "schema", "endpoint". Traducir: "la conexión entre sistemas", "la estructura de datos", etc.
2. **Sin código.** Ni snippets, ni nombres de archivos, ni funciones.
3. **Qué y por qué, nunca cómo.** Resultado y motivación, no pasos de implementación.
4. **Una sección "Por proyecto" por cada proyecto cubierto.** Con un solo proyecto, queda una sola sección — no hace falta anunciar que es "multi-proyecto" ni fusionar nada.
5. **El resumen ejecutivo es obligatorio, el resto es opcional si no aplica.** "Bloqueos", "Pendientes cruzados" y el bloque técnico se omiten enteros si no hay nada que decir — no forzar contenido.
6. **Oraciones cortas. Sin bullets anidados.** Tono directo, como explicarle a alguien inteligente que no es dev.
7. **Nunca inventar avances.** Si un proyecto no tuvo movimiento relevante en la semana, decirlo en una línea ("Sin cambios esta semana") en vez de omitir la sección o rellenarla.

---

## Template

```markdown
---
week_start: YYYY-MM-DD
week_end: YYYY-MM-DD
projects: [<nombre>, <nombre>, ...]
author: <nombre inferido del git config o la conversación>
---

# Weekly Report: <YYYY-MM-DD> a <YYYY-MM-DD>

## Resumen ejecutivo

<2-4 oraciones con el panorama general de la semana. Con un solo proyecto, es el
resumen de ese proyecto. Con varios, el hilo común o los hitos más relevantes
entre todos, antes de entrar en el detalle por proyecto.>

## Por proyecto

### <Nombre del proyecto>

**Qué avanzó**
<2-4 oraciones sobre qué cambió o se entregó esta semana, en términos de
funcionalidad o comportamiento observable.>

**Bloqueos o riesgos**
<Opcional. Solo si hay algo concreto frenando el avance. Omitir si no aplica.>

**Próxima semana**
<1-3 oraciones sobre qué sigue.>

<!-- Repetir el bloque "### <Nombre del proyecto>" completo por cada proyecto adicional. -->

## Pendientes / decisiones abiertas

<Opcional. Preguntas o decisiones sin resolver que cruzan proyectos o que
quedan pendientes para la semana siguiente. Omitir si no hay nada relevante.>

---

<!-- BLOQUE TÉCNICO: incluir solo si hay detalles relevantes para el equipo técnico.
     Si no aplica, eliminar esta sección completa. -->

## Para el equipo técnico

<Detalles concretos por proyecto: tasks completadas, áreas del sistema
afectadas, decisiones técnicas relevantes. Puede usar términos técnicos aquí.>
```
