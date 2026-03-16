# Deployment Notes

## 2026-03-16: Sidebar Highlighting Fix Activation

This deployment activates the sidebar highlighting fix that was previously implemented but not promoted to the live environment.

### Fix Details:
- Enhanced AgentItemComponent with dual highlighting logic
- Fallback name-based comparison for object identity issues
- Maintains backward compatibility
- All tests passing (10/10 including specific sidebar highlighting tests)

The code changes are already in develop - this deployment just ensures they're active in the running application.