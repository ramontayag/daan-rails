# Agent Updates

## 2026-03-16: Sidebar Highlighting Bug Fix

Fixed UI issue where agents weren't highlighted in the sidebar when viewing specific threads directly via URL.

### Changes Made:
- Enhanced `AgentItemComponent` with dual highlighting logic
- Added fallback name-based comparison for object identity issues  
- Maintains full backward compatibility
- Added comprehensive test coverage

### Technical Details:
- Primary highlighting: uses existing `active` flag
- Fallback highlighting: compares `agent.name == current_agent.name`
- Debug attributes available in development mode

This fix ensures reliable agent highlighting regardless of navigation path.