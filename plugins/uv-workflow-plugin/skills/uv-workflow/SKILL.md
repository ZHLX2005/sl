---
description: Basic uv workflow operations - create, run, and manage Python projects
---

# UV Workflow Skill

Basic uv operations for Python project management.

## Common Commands

### Create a new project
```bash
uv create project-name
cd project-name
```

### Run a script
```bash
uv run python script.py
```

### Add dependencies
```bash
uv add package-name
uv add --dev dev-package
```

### Sync dependencies
```bash
uv sync
uv sync --locked
```

### Lock dependencies
```bash
uv lock
```

### Update dependencies
```bash
uv update
uv update package-name
```

### Remove dependencies
```bash
uv remove package-name
```

### Create virtual environment
```bash
uv venv
source .venv/bin/activate  # Linux/Mac
.venv\Scripts\activate     # Windows
```

### Run with specific Python version
```bash
uv run --python 3.11 python script.py
```

### Initialize in existing directory
```bash
uv init
uv add fastapi uvicorn
```

## Workflow Example

1. **Create project**: `uv create my-app`
2. **Add dependencies**: `uv add fastapi uvicorn`
3. **Lock**: `uv lock`
4. **Sync**: `uv sync`
5. **Run**: `uv run python main.py`

Be concise and help the user execute these commands.
