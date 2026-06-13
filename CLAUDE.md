# RubyWM Commands & Style Guide

## Run Commands
- Start WM: `ruby rubywm.rb`
- With DRb: `ruby rubywm.rb --drb`
- Debug mode: `ruby rubywm.rb --debug`
- Install dependencies: `bundle install`

## Code Style
- Indentation: 2 spaces
- Naming: CamelCase for classes, snake_case for methods/variables
- String literals: Use double quotes with interpolation, single quotes otherwise
- Hashes: Use symbol keys (:key => value or key: value)
- Error handling: Use explicit rescue blocks, log errors with pp
- Thread safety: Set Thread.abort_on_exception = true for better debugging
- Documentation: Add comments for complex logic and public interfaces
- Keep code minimal - this is intended to be <1K LOC total

## Architecture
- Node-based tree structure for window layout
- Observer pattern for client messages
- YAML configuration for desktop layouts
- No keyboard handling - deferred to tools like sxhkd
- Communication via X11 ClientMessage events