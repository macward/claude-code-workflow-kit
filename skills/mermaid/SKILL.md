---
name: mermaid
description: "Generate and render a Mermaid diagram from a description. Supports flowcharts and sequence diagrams. Renders the result using the Mermaid Chart MCP tool."
---

# Mermaid Diagram

Generates a Mermaid diagram from a description and renders it.

## Usage

```
/mermaid <diagram description>
/mermaid flowchart <description>
/mermaid sequence <description>
```

If the user doesn't specify a type, infer it from context:
- Flows, decisions, pipelines, states → `flowchart`
- Interactions between components, API calls, messages → `sequenceDiagram`

## Process

### 1. Understand the context

- Read the full argument.
- If the description is ambiguous, ask **a single question** to clarify the type or the main actors. Don't ask more than once.

### 2. Generate the Mermaid code

Produce the diagram using the correct syntax for the type.

**Flowchart:**
```
flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Action]
    B -->|No| D[Other action]
```

Rules:
- Use `TD` (top-down) by default. Switch to `LR` only if the diagram is very wide.
- Nodes with descriptive text, not cryptic IDs.
- Use `-->` for flow, `-->|label|` when the label adds real information.
- Subgraphs to group responsibilities when there are more than 6 nodes.

**Sequence diagram:**
```
sequenceDiagram
    participant Client
    participant API
    participant DB
    Client->>API: request
    API->>DB: query
    DB-->>API: result
    API-->>Client: response
```

Rules:
- Declare all participants at the start with `participant`.
- Use `->>` for synchronous calls, `-->>` for responses.
- Use `activate`/`deactivate` for long operations.
- Group with `rect` or `loop`/`alt`/`opt` when the flow requires it.

**Diagram quality:**
- Prefer clarity over exhaustiveness — omit details that don't change understanding.
- Names in the language the user uses (Spanish or English, consistently).
- No abbreviations in node labels unless they are well-known acronyms.

### 3. Show the code

Present the code block before rendering:

```mermaid
<generated code>
```

### 4. Render

Call the MCP tool to validate and render:

```
mcp__claude_ai_Mermaid_Chart__validate_and_render_mermaid_diagram(
  code=<mermaid code>
)
```

If the tool returns a syntax error, fix the code and retry **once** before reporting the error to the user.

### 5. Confirm

Show the rendered result. If the user asks for adjustments, iterate from step 2 without asking more than necessary.

## Rules

1. Don't generate diagrams with more than ~15 nodes unless the user explicitly asks — they are hard to read.
2. If the context involves data from the current project (components, services, models), read the relevant files before generating.
3. Never invent actors or flows the user didn't describe.
4. If the requested diagram type is neither flowchart nor sequence, generate the correct Mermaid code for that type and render it the same way.
