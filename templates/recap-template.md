# Recap Template

Plantilla para documentos de resumen ejecutivo generados por `/meridian-recap`. Lenguaje claro, sin jerga técnica, dirigido al equipo completo.

---

## Authoring rules

1. **Sin tecnicismos sin explicación.** No "refactor", "PR", "async", "schema", "endpoint". Si hay que mencionarlo, traducirlo: "la conexión entre sistemas", "la estructura de datos", etc.
2. **Sin código.** Ni snippets, ni nombres de archivos, ni funciones.
3. **Qué y por qué, nunca cómo.** Describir el resultado y la motivación — no los pasos de implementación.
4. **El bloque técnico es opcional.** Solo incluirlo si hay detalles concretos útiles para el equipo técnico. Si no hay nada relevante, omitirlo completamente.
5. **Oraciones cortas.** Sin bullets anidados. Tono directo.

---

## Template

```markdown
---
date: YYYY-MM-DD
project: <nombre del proyecto>
author: <nombre inferido del git config o la conversación>
topic: <tema o título de la sesión>
---

# Recap: <título descriptivo>

## ¿Qué se hizo?

<2–4 oraciones describiendo qué cambió o se entregó. Hablar en términos de
funcionalidad o comportamiento observable. Sin tecnicismos.>

Ejemplo: "Ahora es posible filtrar la lista de documentos por estado o por tema,
lo que antes requería revisar todo manualmente."

## ¿Por qué se hizo?

<La motivación o necesidad que originó el trabajo. Un problema resuelto,
una mejora pedida, o una decisión del equipo.>

## ¿Qué impacto tiene?

<Cómo afecta a quienes usan el sistema o al equipo. Qué mejoró, qué se
simplificó, qué problema ya no existe.>

## Pendientes

<Opcional. Solo si quedó algo fuera de esta sesión o hay pasos siguientes claros.
Omitir si no hay nada relevante.>

---

<!-- BLOQUE TÉCNICO: incluir solo si hay detalles relevantes para el equipo técnico.
     Si no aplica, eliminar esta sección completa. -->

## Para el equipo técnico

<Detalles concretos: tasks completadas, áreas del sistema afectadas, decisiones
técnicas relevantes. Puede usar términos técnicos aquí.>
```
