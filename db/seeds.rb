# Agents load from MD files at boot — no DB records needed.
# This file is here for future seed data (memories, initial chats, etc.)
puts "Agents available: #{Daan::AgentRegistry.all.map(&:display_name).join(', ')}"
