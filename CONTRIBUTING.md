# Contributing to ClaudeUsageBar

Thank you for your interest in contributing to ClaudeUsageBar!

## Bug Reports

When filing a bug report, please include:

1. **macOS version** (e.g., macOS 14.0)
2. **Steps to reproduce** the issue
3. **Expected behavior** vs **actual behavior**
4. **Error messages** (click the menu bar item to see details)

## Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly on macOS
5. Commit with clear messages
6. Push to your fork
7. Open a Pull Request

## Code Style

- Follow Swift conventions and Apple's API Design Guidelines
- Use meaningful variable and function names
- Keep functions focused and small
- Add comments only for non-obvious logic

## Important Notes

This app uses an **undocumented API** from Anthropic. Be aware that:

- The API may change without notice
- Breaking changes may require updates to the parsing logic
- Test any API-related changes carefully

## Development Setup

1. Clone the repo
2. Open `ClaudeUsageBar.xcodeproj` in Xcode 15+
3. Build and run (Cmd+R)

Or use the command line:

```bash
./build.sh
open build/Build/Products/Release/ClaudeUsageBar.app
```

## Questions?

Open an issue for any questions about contributing.
