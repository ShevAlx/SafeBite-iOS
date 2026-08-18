# ProductScanner — project context

Native SwiftUI app (iOS 16+): scan a product's barcode/photo → ingredients, allergens, Nutri-Score via Open Food Facts, with a fallback to Google Cloud Vision + OCR. Details in `README.md`.

## Project custom agents

Tailored to this project, defined in `.claude/agents/`:

| Agent | Purpose | Tools |
|---|---|---|
| `swiftui-frontend` | Implements SwiftUI screens and ViewModels (camera/scanner, product card, allergy profile), keeps the Models/Services/ViewModels/Views structure consistent | Read, Edit, Write, Bash, Grep, Glob |
| `ios-designer` | Thinks through UX/UI per Apple HIG — layouts, loading/error states, accessibility (Dynamic Type, VoiceOver, not relying on color alone for allergens). Doesn't write code, only proposes structure | Read, Grep, Glob |

Usual order: `ios-designer` proposes a screen layout → `swiftui-frontend` implements it in code.

The standard Claude Code agents (`backend-dev` — for a future Vision API key proxy backend, `security-reviewer`, `qa-test-engineer`) are also available with no extra setup.
