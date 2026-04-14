---
name: ve-workflow
description: Use when implementing Vue 3 + Vite frontend features in this project. Triggers on component creation, modification, bug fixes, or any frontend development task.
---

# VE Frontend Workflow

Complete frontend development workflow for this Vue 3 + Vite component demo system.

## Component Auto-Discovery System

This project uses automatic component discovery. **Every component must follow this structure:**

```
src/components/{ComponentName}/
├── component.js    # Required: Component configuration
└── index.vue       # Required: Component implementation
```

### component.js Required Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Must match directory name exactly |
| `title` | string | Yes | Display name in UI |
| `description` | string | Yes | Component description |
| `version` | string | Yes | Semantic version |
| `group` | string | Yes | Main category (e.g., 'Three.js', 'DataTable') |
| `category` | string | Yes | Sub-category |
| `tags` | array | Yes | Search/filter tags |
| `component` | string | Yes | Path to `.vue` file (use `'./index.vue'`) |

### Optional Fields

```javascript
route: {
  path: '/custom-path',     // Custom route, defaults to /components/{name}
  meta: {
    title: 'Page Title',
    icon: '🎨'
  }
},
fullscreen: true,          // Default: true
dependencies: [],           // External deps (vue, vue-router, three already内置)
defaultProps: {}           // Default props passed to component
```

## Development Workflow

### 1. Before Writing Code

- [ ] Understand the task requirement
- [ ] Identify which group/category the component belongs to
- [ ] Check existing components for patterns: `src/components/{group}/`

### 2. Creating/Modifying Components

**Creating new component:**
```bash
mkdir -p src/components/{GroupName}/{ComponentName}
```

**Follow naming convention:**
- Directory name = component name (PascalCase)
- `component.js` - configuration
- `index.vue` - implementation

### 3. Syntax & Error Checking

**Before committing, ALWAYS run build to check for errors:**

```bash
pnpm run build
```

**Build output indicates:**
- `dist/` generated → Syntax OK
- Errors shown → Fix before proceeding

**Common errors to watch for:**
- Missing required fields in `component.js`
- Vue template syntax errors
- Import path issues
- Missing dependencies

### 4. After Task Completion

**CRITICAL: Push to GitHub to trigger GitHub Actions deployment**

```bash
# Stage changes
git add .

# Commit with descriptive message
git commit -m "description of changes"

# Push to trigger deployment
git push origin {current-branch}
```

**GitHub Actions will:**
1. Build Docker image
2. Deploy to server via SSH

## Workflow Quick Reference

| Step | Action | Command |
|------|--------|---------|
| 1 | Create/modify component | Edit files in `src/components/` |
| 2 | Test locally | `pnpm run dev` |
| 3 | Check for errors | `pnpm run build` |
| 4 | Commit changes | `git add . && git commit -m "message"` |
| 5 | Push to GitHub | `git push origin {branch}` |

## Group Categories

| Group | Purpose | Examples |
|-------|---------|----------|
| `Three.js` | 3D rendering | Barrage3D, CyberTemple |
| `DataTable` | Table components | BryntumGridTable, RevoGridTable |
| `canvas` | Canvas-based | KnowledgeGraph, Whiteboard |
| `Basic` | Basic demos | HelloWorld |
| `huang` | Custom components | gis, map, report |

## Common Mistakes

| Mistake | Prevention |
|---------|------------|
| Missing `component.js` | Always create with required fields |
| `name` doesn't match directory | Verify exact match (case-sensitive) |
| Build errors not caught | Always run `pnpm run build` before commit |
| Not pushing after task | Git push triggers GitHub Actions deployment |

## Project Structure

```
ve/
├── src/
│   ├── components/          # Auto-discovered components
│   │   ├── {Group}/
│   │   │   └── {Component}/
│   │   │       ├── component.js
│   │   │       └── index.vue
│   ├── views/
│   │   ├── Home.vue         # Component grid
│   │   └── ComponentView.vue # Fullscreen display
│   ├── router/
│   │   └── index.js         # Dynamic route registration
│   └── utils/
│       └── componentDiscovery.js
├── .github/workflows/
│   └── deploy.yml           # Triggers on push to deploy branch
└── package.json
```

## Git Branch Strategy

- `deploy` - Production deployment branch (GitHub Actions auto-deploys)
- Feature branches → PR to `deploy` → Push triggers deployment
