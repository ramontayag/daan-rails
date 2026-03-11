# Agent Resource Manager

The Agent Resource Manager is a specialized agent that acts like an HR manager for the Daan agent team. It provides tools to create new agents and modify existing agent configurations.

## Purpose

- **Create New Agents**: Generate properly configured agent files with validation
- **Modify Existing Agents**: Update agent properties, tools, and delegation relationships
- **Maintain Agent Quality**: Ensure proper agent configuration and workflow hierarchy

## Tools

### CreateAgent

Creates new agent configuration files with proper validation.

**Parameters:**
- `agent_name` (required): Internal identifier (lowercase, underscores only)
- `display_name` (required): Human-readable name
- `description` (required): Agent's role and capabilities
- `tools` (optional): Array of tool class names
- `delegates_to` (optional): Array of agent names this agent can delegate to
- `workspace` (optional): Relative workspace path
- `model` (optional): AI model to use (defaults to claude-sonnet-4-20250514)
- `max_turns` (optional): Maximum conversation turns (defaults to 10)

**Validation:**
- Agent name format (lowercase letters, numbers, underscores only)
- No duplicate agent names
- Tool class existence
- Delegate agent existence

**Example:**
```ruby
CreateAgent.execute(
  agent_name: "data_analyst",
  display_name: "Data Analyst", 
  description: "Analyzes data and generates reports for business insights",
  tools: ["Daan::Core::Read", "Daan::Core::Write", "Daan::Core::ReportBack"],
  workspace: "tmp/workspaces/data_analyst"
)
```

### EditAgent

Modifies existing agent configurations with selective updates.

**Parameters:**
- `agent_name` (required): Name of agent to edit
- `display_name` (optional): New display name
- `description` (optional): New role description  
- `tools` (optional): New tools array (empty array removes tools)
- `delegates_to` (optional): New delegation array (empty array removes delegates)
- `workspace` (optional): New workspace path (empty string removes workspace)
- `model` (optional): New AI model
- `max_turns` (optional): New maximum turns

**Validation:**
- Agent must exist
- Tool class existence (if updating tools)
- Delegate agent existence (if updating delegates)

**Example:**
```ruby
EditAgent.execute(
  agent_name: "data_analyst",
  display_name: "Senior Data Analyst",
  tools: ["Daan::Core::Read", "Daan::Core::Write", "Daan::Core::ReportBack", "DataAnalytics::ChartGenerator"]
)
```

## Access Control

The Agent Resource Manager is accessible to the Chief of Staff agent, allowing for proper workflow delegation:

1. Human requests agent management tasks from Chief of Staff
2. Chief of Staff delegates to Agent Resource Manager
3. Agent Resource Manager performs the requested operations
4. Results are reported back through the delegation chain

## Integration

### Chief of Staff Integration

The Chief of Staff has been updated to delegate agent management tasks:

```yaml
delegates_to:
  - engineering_manager      # For technical work
  - agent_resource_manager   # For agent management
```

### Agent File Format

Agents are stored as markdown files with YAML frontmatter in `lib/daan/core/agents/`:

```yaml
---
name: agent_name
display_name: Human Readable Name
model: claude-sonnet-4-20250514
max_turns: 10
workspace: tmp/workspaces/agent_name  # optional
tools:                                # optional
  - Daan::Core::Read
  - Daan::Core::Write
delegates_to:                         # optional
  - other_agent_name
---
The agent's system prompt and role description goes here.
```

## Best Practices

### When Creating Agents:
- Use clear, descriptive names and display names
- Assign only necessary tools for the agent's role
- Consider workspace requirements for file system access
- Set up logical delegation hierarchies
- Write clear, specific role descriptions

### When Editing Agents:
- Make targeted changes based on specific needs
- Preserve existing configuration unless specifically changing it
- Validate changes don't break agent workflows
- Test delegation chains after modifications

### Tool Assignment Guidelines:
- **Read/Write**: For agents that need file system access
- **DelegateTask**: For management agents that coordinate others
- **ReportBack**: For agents that report to delegators
- **Specialized Tools**: Only assign tools specific to the agent's domain

### Delegation Best Practices:
- Maintain clear hierarchies (avoid circular dependencies)
- Follow the existing pattern: Chief of Staff → Managers → Specialists
- Ensure delegated agents have appropriate tools for delegated tasks

## Examples

### Creating a Code Reviewer Agent:
```ruby
CreateAgent.execute(
  agent_name: "code_reviewer",
  display_name: "Code Reviewer",
  description: "Reviews code changes for quality, security, and best practices. Provides detailed feedback and suggestions for improvements.",
  tools: ["Daan::Core::Read", "Daan::Core::ReportBack"],
  workspace: "tmp/workspaces/code_reviewer"
)
```

### Creating a Project Manager Agent:
```ruby  
CreateAgent.execute(
  agent_name: "project_manager", 
  display_name: "Project Manager",
  description: "Manages project timelines, coordinates between team members, and tracks deliverables.",
  tools: ["Daan::Core::DelegateTask", "Daan::Core::ReportBack"],
  delegates_to: ["developer", "code_reviewer"]
)
```

### Updating an Existing Agent:
```ruby
EditAgent.execute(
  agent_name: "developer",
  tools: ["Daan::Core::Read", "Daan::Core::Write", "Daan::Core::ReportBack", "Git::Operations"]
)
```

## Error Handling

Both tools provide comprehensive error messages for common issues:

- Invalid agent name format
- Duplicate agent names  
- Non-existent tool classes
- Non-existent delegate agents
- File parsing errors
- Registry registration failures

Errors are returned as strings starting with "Error:" and include specific details about what went wrong.