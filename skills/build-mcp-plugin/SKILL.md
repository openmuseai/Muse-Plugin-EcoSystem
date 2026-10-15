---
name: build-mcp-plugin
description: Build, test, and prepare a third-party MCP plugin for the OpenMuse marketplace using public MCP, MCPB, MCP Registry, A2UI, or MCP Apps standards. Use when a developer asks an agent to create or publish a plugin; do not use for built-in Flutter features.
---

# Build an independent plugin

Read the [developer guide](../../docs/DEVELOPER-GUIDE.zh-CN.md) and [architecture](../../docs/ARCHITECTURE.zh-CN.md) for the target platform. Ask the developer which client version to test only if they require a version other than `latest`; resolve that choice from [`compatibility/clients.json`](../../compatibility/clients.json).

Create a standalone MCP server. Keep the package free of client source imports, private Manifest fields, Host command names, absolute local paths, and embedded secrets. Use standard JSON Schema to describe inputs and outputs. For user-selected files use `contentEncoding: base64` and `contentMediaType`. Desktop local artifacts use MCPB; Mobile/Web connections use MCP Streamable HTTP with A2UI over MCP or MCP Apps when a UI is needed.

Run an independent MCP client against the server, then package and verify the artifact digest. The GenOffice PPTX example in `plugins/genoffice-pptx` is the runnable reference. Show the developer the exact package, `server.json`, tested client version, target platforms, tool list, permissions/data handling, and test result before publication.

Only upload or submit when the user has asked to publish. Submission enters review; do not claim public availability until the Registry lists the approved version. Never use reviewer credentials in a developer workflow.
