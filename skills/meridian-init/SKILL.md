---
name: meridian-init
description: "Initialize a new vibe workspace by calling init_project. Single-purpose: creates the standard folder structure on the Meridian server. Does not create or modify any local files."
---

# Meridian Init

Create a new vibe workspace via `init_project`. Nothing else.

## Process

1. Ask the user for the project name. Validate: letters, numbers, hyphens only.
2. Call:
   ```
   mcp__meridian__init_project(project=<name>)
   ```
3. Confirm to the user that the workspace was created and remind them to add `meridian-project: <name>` to the project's CLAUDE.md.

## If `init_project` is not available

It is an **opt-in tool**: the server only registers it when `MERIDIAN_TOOLSETS`
includes `admin`. If it is missing, that is a server configuration, not a bug —
say so and stop, rather than looking for another way in. Bootstrapping a
workspace is rare enough that the tool is not worth the schema every session
pays for it, which is why it is gated.

To enable it, the operator sets `MERIDIAN_TOOLSETS=admin` (comma-separated with
any other groups) and restarts the server.

## Hard rules

- Only `init_project`. No other MCP tools, no shell commands, no file writes.
- Do not create or modify CLAUDE.md.
- If the MCP server is not connected, stop and tell the user.
