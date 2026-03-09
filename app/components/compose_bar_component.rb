class ComposeBarComponent < ViewComponent::Base
  def initialize(agent:)
    @agent = agent
  end

  private

  attr_reader :agent
end
